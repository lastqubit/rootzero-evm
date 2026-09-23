import { expect } from "chai";
import { ethers } from "ethers";
import { mkdirSync, writeFileSync } from "node:fs";
import { deploy, getProvider, getSigner, hostId } from "./helpers/setup.js";
import { encodeAmountBlock, encodeBalanceBlock, encodeContextBlock } from "./helpers/blocks.js";

describe("Burn loop versus CommandBase.runCommand", function () {
  this.timeout(180_000);
  const method = "burn(bytes)";
  const account = ethers.zeroPadValue("0x22", 32);
  const asset = ethers.zeroPadValue("0x11", 32);
  let loop: Awaited<ReturnType<typeof deploy>>;
  let run: Awaited<ReturnType<typeof deploy>>;

  before(async () => {
    const commander = await hostId(await (await getSigner()).getAddress());
    loop = await deploy("TestBurnLoopHost", commander);
    run = await deploy("TestBurnHost", commander);
  });

  it("compares transaction gas, emitted events, return values, and runtime size", async () => {
    const rows: { count: number; loopGas: number; runGas: number; delta: number }[] = [];
    for (const count of [0, 1, 2, 8, 32, 128]) {
      const state = ethers.concat(Array.from({ length: count }, (_, i) => encodeBalanceBlock(asset, BigInt(i + 1))));
      const context = encodeContextBlock(account, state, "0x");
      expect(Array.from(await loop[method].staticCall(context))).to.deep.equal(["0x", 0n]);
      expect(Array.from(await run[method].staticCall(context))).to.deep.equal(["0x", 0n]);
      const before = await (await loop[method](context)).wait();
      const after = await (await run[method](context)).wait();
      const events = (receipt: any) => receipt.logs.map((log: any) => ({ topics: [...log.topics], data: log.data }));
      expect(after.logs.length).to.equal(count);
      expect(events(after)).to.deep.equal(events(before));
      rows.push({ count, loopGas: Number(before.gasUsed), runGas: Number(after.gasUsed),
        delta: Number(after.gasUsed - before.gasUsed) });
    }
    const provider = await getProvider();
    const runtimeBytes = {
      loop: ethers.dataLength(await provider.getCode(await loop.getAddress())),
      run: ethers.dataLength(await provider.getCode(await run.getAddress())),
    };
    mkdirSync(".npm-cache", { recursive: true });
    writeFileSync(".npm-cache/burn-run-results.json", JSON.stringify({
      compiler: "0.8.35", optimizerRuns: 200, evmTarget: "cancun",
      measurement: "Transaction receipt gas; identical calldata, selector, access check, and event-only hook",
      rows, runtimeBytes,
    }, null, 2) + "\n");
    console.table(rows);
    console.log("Burn runtime bytes:", runtimeBytes);
  });

  it("preserves revert data for malformed sources and access failures", async () => {
    const balance = encodeBalanceBlock(asset, 1n);
    const amount = encodeAmountBlock(asset, 1n);
    const valid = encodeContextBlock(account, balance, "0x");
    async function failure(host: any, context: string) {
      try {
        await host[method].staticCall(context);
      } catch (error: any) {
        const data = error.data ?? error.info?.error?.data;
        if (typeof data !== "string") throw error;
        return data;
      }
      throw new Error("Expected a revert");
    }
    for (const context of [
      "0x", "0x1234", amount, ethers.concat([valid, "0x00"]), ethers.concat([valid, valid]),
      encodeContextBlock(account, amount, "0x"),
      encodeContextBlock(account, ethers.concat([balance, amount]), "0x"),
      encodeContextBlock(account, ethers.dataSlice(balance, 0, 71), "0x"),
      encodeContextBlock(account, balance, amount),
      encodeContextBlock(account, "0x", amount),
    ]) {
      expect(await failure(run, context)).to.equal(await failure(loop, context));
    }
    const stranger = await getSigner(1);
    expect(await failure(run.connect(stranger), valid)).to.equal(await failure(loop.connect(stranger), valid));
  });
});
