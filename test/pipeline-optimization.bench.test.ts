import { expect } from "chai";
import { mkdirSync, writeFileSync } from "node:fs";
import { ethers } from "ethers";
import { commandId, deploy, getProvider } from "./helpers/setup.js";
import { concat, encodeStepBlock, encodeUserAccount } from "./helpers/blocks.js";
import {
  authorizeCommander, commanderCashout, commanderCodeSize, commanderDeadline,
  commanderRoundtrip, deployCommanderPair, upgradeCommander,
} from "./helpers/commander-proxy.js";

describe("Pipeline parser and credit gas", function () {
  this.timeout(120_000);
  it("measures internal and external steps with identical command work", async () => {
    const host = await deploy("TestPipelineOptimization");
    const rows: { mode: string; count: number; gas: number }[] = [];
    for (const [mode, id] of [["internal", await host.localId()], ["external", await host.externalId()]] as const) {
      for (const count of [0, 1, 2, 4, 8, 16]) {
        const steps = concat(...Array(count).fill(encodeStepBlock(id, 0n, "0x")));
        const [gas, remaining] = await host.measure.staticCall(steps, 123n, "0x");
        expect(remaining).to.equal(123n);
        rows.push({ mode, count, gas: Number(gas) });
      }
    }
    console.table(rows);
  });
});

describe("Main-style commander proxy gas", function () {
  this.timeout(180_000);

  it("compares direct, UUPS and upgraded pipelines with matching work and funded ledgers", async () => {
    const pair = await deployCommanderPair();
    const remote = await deploy("TestRemoteCommand");
    const remoteId = await commandId("noop(bytes)", remote);
    const account = encodeUserAccount(pair.owner);
    const provider = await getProvider();
    for (const host of [pair.direct, pair.proxy]) {
      await host.rootzero("0x", commanderDeadline, { value: ethers.parseEther("1") });
      await authorizeCommander(host, [remoteId, await commandId("executePayable(bytes)", host, 3n)]);
    }

    const cases = [
      { workload: "empty", count: 0 },
      { workload: "deposit", count: 0 },
      ...[0, 1, 4, 8, 16].map(count => ({ workload: "local checks", count })),
      ...[1, 4, 8, 16].map(count => ({ workload: "external commands", count })),
      ...[1, 4, 8, 16].map(count => ({ workload: "self-call governance", count })),
      { workload: "cashout", count: 1 },
    ];
    const measurements: any[] = [];
    const bytecodes: Record<string, number> = {
      direct: await commanderCodeSize(pair.direct),
      implementationV1: await commanderCodeSize(pair.implementation),
      proxy: await commanderCodeSize(pair.proxy),
    };

    async function measure(mode: string, host: any) {
      for (const { workload, count } of cases) {
        const governance = workload === "self-call governance";
        let steps = "0x";
        if (workload === "local checks") steps = await commanderRoundtrip(host, count);
        if (workload === "external commands") steps = await commanderRoundtrip(host, count, remoteId);
        if (workload === "cashout") steps = await commanderCashout(host, 7n);
        if (governance) steps = concat(...Array(count).fill(
          encodeStepBlock(await commandId("executePayable(bytes)", host, 3n), 0n, "0x")));
        expect(ethers.dataLength(steps)).at.most(4096);
        const samples: { gas: number; intrinsic: number; execution: number; calldataFloor: number;
          floorBound: boolean; delegatecalls: number }[] = [];
        for (let i = 0; i < 3; ++i) {
          const before = await host.balanceOf(account, await host.nativeAsset());
          const tx = await host[governance ? "govern" : "rootzero"](steps, commanderDeadline,
            { value: workload === "deposit" ? 1n : 0n, gasLimit: 5_000_000 });
          const receipt = await tx.wait();
          const data = ethers.getBytes(tx.data);
          const intrinsic = 21_000 + data.reduce((sum, byte) => sum + (byte === 0 ? 4 : 16), 0);
          const gas = Number(receipt.gasUsed);
          const floor = 21_000 + data.reduce((sum, byte) => sum + (byte === 0 ? 10 : 40), 0);
          const delta = workload === "deposit" ? 1n : workload === "cashout" ? -7n : 0n;
          expect(await host.balanceOf(account, await host.nativeAsset())).eq(before + delta);
          const trace = await provider.send("debug_traceTransaction", [tx.hash,
            { disableMemory: true, disableStack: true, disableStorage: true }]);
          const ops = trace.structLogs;
          expect(trace.failed).eq(false);
          expect(ops[0].depth).eq(ops.at(-1).depth);
          // Outer-frame gas delta includes child execution, excludes transaction
          // calldata pricing and measures gross work before SSTORE refunds.
          const execution = Number(ops[0].gas) - Number(ops.at(-1).gas) + Number(ops.at(-1).gasCost);
          const delegates = ops.filter((step: any) => step.op === "DELEGATECALL").length;
          const expected = mode === "direct" ? 0 : governance ? count + 1 : 1;
          expect(delegates).eq(expected);
          samples.push({ gas, intrinsic, execution, calldataFloor: floor, floorBound: gas === floor, delegatecalls: delegates });
        }
        const median = (key: "gas" | "execution") => samples.map(s => s[key]).sort((a, b) => a - b)[1];
        measurements.push({ mode, workload, count, stepsBytes: ethers.dataLength(steps),
          gas: median("gas"), execution: median("execution"), samples });
      }
    }

    await measure("direct", pair.direct);
    await measure("proxy V1", pair.proxy);
    const v2 = await upgradeCommander(pair.proxy);
    // EIP-1967 implementation slot; record deployed V2 size separately from the proxy.
    const slot = "0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc";
    const v2Address = ethers.getAddress(ethers.dataSlice(await provider.getStorage(await v2.getAddress(), slot), 12));
    bytecodes.implementationV2 = ethers.dataLength(await provider.getCode(v2Address));
    await measure("proxy V2", v2);

    const rows = cases.map(({ workload, count }) => {
      const find = (mode: string) => measurements.find(row => row.mode === mode && row.workload === workload && row.count === count);
      const direct = find("direct"), proxy = find("proxy V1"), v2 = find("proxy V2");
      return { workload, count, directGas: direct.gas, proxyGas: proxy.gas, upgradedGas: v2.gas,
        proxyExecutionOverhead: proxy.execution - direct.execution,
        upgradedExecutionOverhead: v2.execution - direct.execution,
        proxyTxPercent: Number((100 * (proxy.gas - direct.gas) / direct.gas).toFixed(2)) };
    });
    console.table(rows);
    mkdirSync("docs/benchmarks", { recursive: true });
    writeFileSync("docs/benchmarks/COMMANDER_PROXY.json", JSON.stringify({
      compiler: "0.8.35", optimizer: { viaIR: true, runs: 200 }, evmTarget: "cancun",
      openzeppelin: "5.6.1", samplesPerCase: 3, chainId: String((await provider.getNetwork()).chainId),
      notes: [
        "Rootzero with explicit Runtime execution identity; measurements correspond to the source revision containing this report.",
        "Direct Ownable2Step and UUPS Ownable2StepUpgradeable share the Main-style core and ReentrancyGuardTransient.",
        "V2 adds ExecuteDebitAccount, one dispatch branch, and an initialized storage word.",
        "Every sample is a separate transaction: initially cold implementation and proxy slot, pre-funded native ledger.",
        "gas is actual receipt gas including refunds and any EIP-7623 calldata floor; intrinsic records 21000 plus 4/16 per calldata byte.",
        "execution is the outer-frame opcode-trace gas delta, including child calls but excluding intrinsic gas, refunds and the calldata floor.",
        "Local/external counts exclude the surrounding bootstrap and creditAccount steps.",
        "External commands use the same non-upgradeable TestRemoteCommand.noop target; self-call governance uses executePayable with empty input.",
        "No gas thresholds; opcode traces verify one delegation for local/external pipelines versus N+1 for self-calls.",
      ], bytecodes, rows, measurements,
    }, null, 2) + "\n");
  });
});
