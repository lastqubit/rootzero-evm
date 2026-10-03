import { expect } from "chai";
import { ethers } from "ethers";
import { mkdirSync, writeFileSync } from "node:fs";
import { deploy, getProvider } from "./helpers/setup.js";
import { encodeBlock, encodeContextBlock, encodeBalanceBlock, Keys } from "./helpers/blocks.js";

const account = ethers.toBeHex(7, 32);
const spec = (key: string, hint: number) => (BigInt(key) << 224n) | (BigInt(hint) << 136n);
const balanceSpec = spec(Keys.Balance, 64);
const bytesSpec = spec(Keys.Bytes, 128);
const balance = encodeBalanceBlock(account, 123n);
const repeat = (data: string, count: number) => ethers.concat(Array(count).fill(data));
async function pair(state: bigint, input: bigint, output: bigint, flags = 0) {
  return [await deploy("ExecutionPlanCurrent", state, input, output, flags),
    await deploy("ExecutionPlanCandidate", state, input, output, flags)];
}
async function outcome(helper: any, data: string) {
  try { return { value: Array.from(await helper.measure(data, ethers.MaxUint256)).slice(1) }; }
  catch (error: any) {
    const revert = error.data ?? error.info?.error?.data;
    expect(revert).to.be.a("string");
    return { error: revert };
  }
}

describe("Execution plan candidate", function () {
  this.timeout(180_000);
  it("preserves allocation and measures opening and execution gas", async () => {
    const rows: any[] = [];
    for (const mode of ["none", "state", "input", "both", "empty-state", "variable", "mixed"]) {
      const variable = mode === "variable" || mode === "mixed";
      const stateSpec = ["state", "both", "empty-state"].includes(mode) ? balanceSpec : 0n;
      const inputSpec = variable ? bytesSpec : ["input", "both", "empty-state"].includes(mode) ? balanceSpec : 0n;
      for (const allocate of [false, true]) {
        const [current, candidate] = await pair(stateSpec, inputSpec, allocate ? balanceSpec : 0n);
        for (const count of [0, 1, 4, 16]) {
          const state = stateSpec && mode !== "empty-state" ? repeat(balance, count) : "0x";
          const input = variable ? repeat(encodeBlock(Keys.Bytes, "0x123456"), count)
            + (mode === "mixed" && count ? balance.slice(2) : "")
            : inputSpec ? repeat(balance, count) : "0x";
          const context = encodeContextBlock(account, state, input);
          const a = await current.measure(context, ethers.MaxUint256);
          const b = await candidate.measure(context, ethers.MaxUint256);
          expect(Array.from(b).slice(1)).deep.eq(Array.from(a).slice(1));
          const expectedCount = stateSpec ? (mode === "empty-state" ? 0 : count) : inputSpec ? count : 1;
          expect(a.outputCur >> 32n).eq(BigInt(allocate ? 72 * expectedCount : 0));
          const ar = await current.run.staticCall(context, 19);
          const br = await candidate.run.staticCall(context, 19);
          expect(Array.from(br).slice(1)).deep.eq(Array.from(ar).slice(1));
          rows.push({ mode, allocate, count, openCurrent: Number(a[0]), openCandidate: Number(b[0]),
            openDelta: Number(b[0] - a[0]), runCurrent: Number(ar[0]), runCandidate: Number(br[0]), runDelta: Number(br[0] - ar[0]) });
        }
      }
    }
    console.table(rows.filter(r => r.allocate && r.count === 4));
    mkdirSync(".npm-cache", { recursive: true });
    writeFileSync(".npm-cache/execution-plan-gas.json", JSON.stringify(rows, null, 2));
  });

  it("preserves exact log bytes and order for all logging combinations", async () => {
    const rows: any[] = [];
    for (let mask = 0; mask < 8; mask++) {
      // Include unrelated public flags to prove they do not become logging flags.
      const flags = (mask << 2) | 131;
      const [current, candidate] = await pair(balanceSpec, balanceSpec, balanceSpec, flags);
      for (const count of [0, 1, 4]) {
        const state = repeat(balance, count);
        const input = repeat(encodeBalanceBlock(account, 456n), count);
        const context = encodeContextBlock(account, state, input);
        const a = await current.run.staticCall(context, 19);
        const b = await candidate.run.staticCall(context, 19);
        expect(Array.from(b).slice(1)).deep.eq(Array.from(a).slice(1));
        const ra = await (await current.run(context, 19)).wait();
        const rb = await (await candidate.run(context, 19)).wait();
        const readLogs = (r: any) => r.logs.map((l: any) => ({ topics: Array.from(l.topics), data: l.data }));
        expect(readLogs(rb)).deep.eq(readLogs(ra));
        const expected = [state, input, a.output].filter((_, i) => mask & (1 << i))
          .map(stream => ({ topics: [], data: ethers.concat([ethers.toBeHex(123, 32), stream]) }));
        expect(readLogs(rb)).deep.eq(expected);
        rows.push({ mask, count, current: Number(a[0]), candidate: Number(b[0]), delta: Number(b[0] - a[0]),
          txDelta: Number(rb.gasUsed - ra.gasUsed) });
      }
    }
    const [current, candidate] = await pair(balanceSpec, balanceSpec, balanceSpec);
    const provider = await getProvider();
    const sizes = { current: ethers.dataLength(await provider.getCode(await current.getAddress())),
      candidate: ethers.dataLength(await provider.getCode(await candidate.getAddress())) };
    console.table(rows.filter(r => r.count === 4));
    console.log("Runtime bytes", sizes);
    writeFileSync(".npm-cache/execution-plan-logs.json", JSON.stringify({ rows, sizes }, null, 2));
  });

  it("preserves rejection of malformed contexts and capacity overflow", async () => {
    const [current, candidate] = await pair(balanceSpec, balanceSpec, balanceSpec);
    const valid = encodeContextBlock(account, balance, balance);
    const vectors = [valid, ethers.concat([valid, "0x00"])];
    for (let n = 0; n < ethers.dataLength(valid); n++) vectors.push(ethers.dataSlice(valid, 0, n));
    for (const offset of [0, 40, 120]) {
      const wrong = ethers.getBytes(valid); wrong[offset] ^= 255; vectors.push(ethers.hexlify(wrong));
      for (const length of [0, 1, 7, 8, 32, 64, 72, 0xffffffff]) {
        const altered = ethers.getBytes(valid); altered.set(ethers.getBytes(ethers.toBeHex(length, 4)), offset + 4);
        vectors.push(ethers.hexlify(altered));
      }
    }
    for (const data of vectors) expect(await outcome(candidate, data), data).deep.eq(await outcome(current, data));
    // Largest payload hint needs 25 bits after adding the block header.
    const maxOutput = spec(Keys.Bytes, 0xffffff);
    const [largeCurrent, largeCandidate] = await pair(balanceSpec, 0n, maxOutput);
    expect((await largeCandidate.plan() >> 160n) & 0xffffffffn).eq(0x1000007n);
    const overflow = encodeContextBlock(account, repeat(balance, 256), "0x");
    const a = await outcome(largeCurrent, overflow), b = await outcome(largeCandidate, overflow);
    expect(a).to.have.property("error");
    expect(b).deep.eq(a);
    console.log("Malformed/boundary vectors", vectors.length + 1);
  });
});
