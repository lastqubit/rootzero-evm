import { expect } from "chai";
import { ethers } from "ethers";
import { writeFileSync } from "node:fs";
import { deploy, getProvider } from "./helpers/setup.js";
import { concat, encodeContextBlock, encodeBalanceBlock, encodeAssetAmountBlock, encodeStateBlock, encodeInputBlock, encodeOutputBlock } from "./helpers/blocks.js";

const names = ["RunnerCurrent", "RunnerSharedLogged", "RunnerSharedUnlogged", "RunnerDirectUnlogged", "RunnerMixedCurrent", "RunnerMixedShared", "RunnerMixedDirect"];
const asset = ethers.toBeHex(123n, 32), account = ethers.toBeHex(1n, 32);
const balance = encodeBalanceBlock(asset, 7n), amount = encodeAssetAmountBlock(asset, 3n);
const record = (data: string) => concat(ethers.toBeHex(123n, 32), data);
async function failure(call: Promise<any>) {
  try { await call; throw new Error("Expected rejection"); }
  catch (error: any) { if (typeof error.data !== "string") throw error; return error.data; }
}

describe("Unlogged command runner candidates", function () {
  this.timeout(180_000);
  it("compares literal shared runners with production and a direct unlogged loop", async () => {
    const provider = await getProvider();
    const rows: any[] = [], sizes: any[] = [], loggedRows: any[] = [];
    for (const mode of [0, 1, 2, 3]) {
      const hosts = await Promise.all(names.map(name => deploy(name, mode, 0)));
      sizes.push({ mode, ...Object.fromEntries(await Promise.all(hosts.map(async (host, i) => [names[i], ethers.dataLength(await provider.getCode(await host.getAddress()))]))) });
      for (const count of [0, 1, 4, 16, 64]) {
        const state = concat(...Array(mode === 2 ? 0 : count).fill(balance));
        const input = concat(...Array(mode >= 2 ? count : 0).fill(amount));
        const context = encodeContextBlock(account, state, input);
        const output = mode === 0 ? "0x" : concat(...Array(count).fill(encodeBalanceBlock(asset, mode === 3 ? 10n : mode === 2 ? 3n : 7n)));
        const gas: number[] = [], execution: number[] = [];
        for (const host of hosts) {
          const result = await host.run.staticCall(context, { value: 17n });
          expect(result[0]).eq(output); expect(result[1]).eq(17n);
          const receipt = await (await host.run(context, { value: 17n })).wait();
          expect(receipt.logs).deep.eq([]);
          gas.push(Number(receipt.gasUsed)); execution.push(Number(result[2]));
        }
        rows.push({ mode, count, gas, execution, saved: gas[0] - gas[2], executionSaved: execution[0] - execution[2], loggedDelta: execution[1] - execution[0], directDelta: execution[2] - execution[3], mixedSaved: gas[4] - gas[5], mixedExecutionSaved: execution[4] - execution[5], mixedDirectSaved: gas[4] - gas[6] });
      }
      const valid = encodeContextBlock(account, mode === 2 ? "0x" : balance, mode >= 2 ? amount : "0x");
      for (const bad of ["0x", concat(valid, "0x00"), ethers.dataSlice(valid, 0, ethers.dataLength(valid) - 1), encodeContextBlock(account, mode === 2 ? "0x" : amount, mode >= 2 ? balance : "0x")]) {
        const errors = await Promise.all(hosts.map(host => failure(host.run.staticCall(bad))));
        expect(errors[0]).eq(ethers.id("InvalidBlock()").slice(0, 10));
        for (const error of errors) expect(error).eq(errors[0]);
      }
    }
    for (const mask of [1, 2, 3, 4, 7]) {
      const hosts = await Promise.all([names[0], names[1], names[4], names[5], names[6]].map(name => deploy(name, 3, mask)));
      for (const count of [0, 1, 4]) {
        const state = concat(...Array(count).fill(balance)), input = concat(...Array(count).fill(amount));
        const output = concat(...Array(count).fill(encodeBalanceBlock(asset, 10n)));
        const expected: string[] = [];
        if (mask & 3) expected.push(record(concat(mask & 1 ? encodeStateBlock(state) : "0x", mask & 2 ? encodeInputBlock(input) : "0x")));
        if (mask & 4) expected.push(record(encodeOutputBlock(output)));
        const gas: number[] = [];
        for (const [i, host] of hosts.entries()) {
          const method = i >= 2 ? host.logged : host.run;
          const context = encodeContextBlock(account, state, input);
          const result = await method.staticCall(context, { value: 17n });
          expect(result[0]).eq(output); expect(result[1]).eq(17n);
          const receipt = await (await method(context, { value: 17n })).wait();
          expect(receipt.logs.map((log: any) => log.data)).deep.eq(expected);
          expect(receipt.logs.every((log: any) => log.topics.length === 0)).eq(true);
          gas.push(Number(receipt.gasUsed));
        }
        loggedRows.push({ mask, count, gas, mixedSharedDelta: gas[3] - gas[2], mixedDirectDelta: gas[4] - gas[2] });
      }
    }
    console.table(rows.map(({ mode, count, saved, executionSaved, loggedDelta, directDelta, mixedSaved, mixedExecutionSaved, mixedDirectSaved }) => ({ mode, count, saved, executionSaved, loggedDelta, directDelta, mixedSaved, mixedExecutionSaved, mixedDirectSaved })));
    console.table(sizes);
    console.table(loggedRows);
    writeFileSync(".npm-cache/unlogged-runner.json", JSON.stringify({ compiler: "0.8.35", viaIR: true, optimizerRuns: 200, evmVersion: "cancun", names, rows, sizes, loggedRows }, null, 2) + "\n");
  });
});
