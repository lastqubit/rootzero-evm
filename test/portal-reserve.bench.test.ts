import { expect } from "chai";
import { ethers } from "ethers";
import { mkdirSync, writeFileSync } from "node:fs";
import { deploy, getProvider, hostId } from "./helpers/setup.js";

describe("Portal explicit reserve benchmark", function () {
  this.timeout(120_000);

  it("measures a fresh cold-slot fallback including costs before CALL", async () => {
    const pipe = await deploy("TestOutOfGasPipe");
    const portal = await deploy("TestPortalGasReserve", await hostId(pipe));
    const provider = await getProvider();
    const results: object[] = [];
    let index = 0;
    for (const priorMemory of [0, 65_536]) {
      for (const bytes of [0, 1, 31, 32, 33, 256, 4096, 65_536]) {
        for (const value of [0n, 7n]) {
          const key = ethers.toBeHex(++index, 32);
          const message = "0x" + "ab".repeat(bytes);
          const tx = await portal.testForward(key, message, priorMemory,
            { value, gasLimit: 200_000 + bytes * 40 + priorMemory });
          const receipt = await tx.wait();
          expect(receipt.status).to.equal(1);
          expect(await portal.getUnresolved(key)).to.equal(ethers.keccak256(message));
          const trace = await provider.send("debug_traceTransaction", [tx.hash,
            { disableMemory: true, disableStorage: true }]);
          const steps = trace.structLogs;
          const callIndex = steps.findIndex((s: any) => s.depth === 1 && s.op === "CALL");
          const gasIndex = steps.slice(0, callIndex).findLastIndex((s: any) => s.op === "GAS");
          const after = steps.slice(callIndex + 1).find((s: any) => s.depth === 1);
          const call = steps[callIndex];
          const requested = Number(BigInt(call.stack.at(-1)));
          const child = steps[callIndex + 1];
          // Prove the explicit limit binds, rather than relying on EIP-150's reserve.
          expect(child.depth).to.equal(2);
          expect(Number(child.gas)).to.equal(requested + (value === 0n ? 0 : 2300));
          const snapshot = Number(steps[gasIndex].gas) - 2;
          const last = steps.at(-1);
          const remaining = Number(last.gas) - Number(last.gasCost);
          const saved = snapshot - requested;
          expect(remaining).to.be.greaterThan(5000);
          const event = receipt.logs.map((log: any) => portal.interface.parseLog(log))
            .find((log: any) => log?.name === "Unresolved");
          expect(event?.args.digest).to.equal(ethers.keccak256(message));
          results.push({ bytes, priorMemory, value: Number(value), reserve: saved,
            requiredReserve: saved - remaining, gasAfterPipe: Number(after.gas),
            gasAfterReturn: remaining });
        }
      }
    }
    mkdirSync(".npm-cache", { recursive: true });
    writeFileSync(".npm-cache/portal-reserve-results.json", JSON.stringify(results, null, 2) + "\n");
    console.table(results);
  });
});
