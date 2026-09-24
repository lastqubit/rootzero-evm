import { expect } from "chai";
import { ethers } from "ethers";
import { mkdirSync, writeFileSync } from "node:fs";
import { deploy } from "./helpers/setup.js";
import { encodeBlock, encodeBytesBlock, encodeStepBlock, encodeCallBlock, encodeContextBlock,
  encodeRelayBlock, encodeDispatchBlock, encodeRecoverBlock, encodeLabelBlock,
  encodeSchemaBlock, encodeAnnotationBlock, encodeBalanceBlock, Keys, exactSpec, rangedSpec } from "./helpers/blocks.js";

const word = ethers.toBeHex(33, 32);
const blob = (size: number) => "0x" + "ab".repeat(size);
const balance = encodeBalanceBlock(word, 11n);
const state = ethers.concat([balance, balance]);
const cases = [
  { name: "unpackBytes", input: encodeBytesBlock(blob(3)), parameter: 0n },
  { name: "unpackStep", input: encodeStepBlock(11n, 22n, blob(3)), parameter: 0n },
  { name: "consumeSpec", input: encodeBytesBlock(blob(3)), parameter: rangedSpec(Keys.Bytes, 0, 0, 0) },
  { name: "consumeKey", input: encodeBytesBlock(blob(3)), parameter: BigInt(Keys.Bytes) },
  { name: "unpackRaw", input: encodeBytesBlock(blob(3)), parameter: rangedSpec(Keys.Bytes, 0, 0, 0) },
  { name: "unpackString", input: encodeBlock(Keys.String, blob(3)), parameter: 0n },
  { name: "unpackContext", input: encodeContextBlock(word, blob(3), blob(5)), parameter: 0n },
  { name: "unpackRelay", input: encodeRelayBlock(blob(3), blob(5)), parameter: 0n },
  { name: "unpackLabel", input: encodeLabelBlock(word, "abc"), parameter: 0n },
  { name: "unpackSchema", input: encodeSchemaBlock(11n, "abc"), parameter: 0n },
  { name: "unpackRecover", input: encodeRecoverBlock(11n, 22n, word, blob(3)), parameter: 0n },
  { name: "unpackCall", input: encodeCallBlock(11n, 22n, blob(3)), parameter: 0n },
  { name: "unpackDispatch", input: encodeDispatchBlock(11n, 22n, blob(3)), parameter: 0n },
  { name: "unpackAnnotation", input: encodeAnnotationBlock(11n, blob(3)), parameter: 0n },
  { name: "tryConsumeEmpty", input: encodeBytesBlock("0x"), parameter: BigInt(Keys.Bytes) },
  { name: "rawState", input: blob(3), parameter: 0n },
  { name: "takeRawState", input: blob(3), parameter: 0n },
  { name: "rawInput", input: blob(3), parameter: 0n },
  { name: "takeRawInput", input: blob(3), parameter: 0n },
  { name: "takeRawBalances", input: blob(3), parameter: 0n },
  { name: "unpack32", input: encodeBlock(Keys.Bytes, blob(32)), parameter: exactSpec(Keys.Bytes, 32) },
  { name: "useValue", input: "0x", parameter: 11n },
];
function config(input: string, stateData = state, parameter = 0n, more: object = {}) {
  return { inputStart: 0, inputEnd: ethers.dataLength(input), stateStart: 0,
    stateEnd: ethers.dataLength(stateData), flags: 3, budget: 100n, parameter, repetitions: 1, ...more };
}
async function outcome(call: () => Promise<any>) {
  try {
    const r = await call(); return { decoders: r.decoders, budget: r.budget, data: r.data };
  } catch (error: any) {
    const data = error.data ?? error.info?.error?.data;
    if (typeof data !== "string") throw error;
    return { error: data };
  }
}
describe("Execution optimization", function () {
  this.timeout(180_000);
  it("benchmarks all changed traversal, decode, and budget paths", async () => {
    const helper = await deploy("TestExecutionOptimization");
    const rows: object[] = [];
    for (let mode = 0; mode < cases.length; mode++) {
      const c = cases[mode];
      const cfg = config(c.input, state, c.parameter);
      const before = await helper.measure(false, mode, state, c.input, cfg);
      const after = await helper.measure(true, mode, state, c.input, cfg);
      expect(after.decoders).to.equal(before.decoders);
      expect(after.budget).to.equal(before.budget);
      expect(after.data).to.equal(before.data);
      expect(after.usedGas, c.name).to.be.lessThan(before.usedGas);
      rows.push({ operation: c.name, before: Number(before.usedGas), after: Number(after.usedGas),
        saved: Number(before.usedGas - after.usedGas) });
    }
    for (const count of [0, 1, 8, 64, 256]) {
      const source = ethers.concat(Array(count).fill(balance));
      const cfg = config("0x", source);
      const before = await helper.measure(false, 19, source, "0x", cfg);
      const after = await helper.measure(true, 19, source, "0x", cfg);
      expect(after.data).to.equal(before.data);
      expect(after.decoders).to.equal(before.decoders);
      expect(after.usedGas).to.be.lessThan(before.usedGas);
      rows.push({ operation: "takeRawBalances", count, before: Number(before.usedGas), after: Number(after.usedGas),
        saved: Number(before.usedGas - after.usedGas) });
    }
    mkdirSync(".npm-cache", { recursive: true });
    writeFileSync(".npm-cache/execution-results.json", JSON.stringify(rows, null, 2) + "\n");
    console.table(rows);
  });

  it("preserves bounds, error order, lane flags, budgets, and cursor words", async () => {
    const helper = await deploy("TestExecutionOptimization");
    for (let mode = 0; mode < cases.length; mode++) {
      const c = cases[mode];
      const samples = [c.input, "0x", "0xffffffff", ethers.dataSlice(c.input, 0, Math.min(7, ethers.dataLength(c.input)))];
      for (const input of samples) {
        const len = ethers.dataLength(input);
        const variations = [ {}, { inputEnd: Math.max(0, len - 1) }, { inputStart: len + 1 },
          { inputEnd: 65536, stateEnd: 65536 }, { flags: 0 }, { flags: 1 }, { flags: 2 },
          { stateStart: ethers.dataLength(state) + 1 }, { flags: (1n << 120n) | 3n },
          { budget: 0 }, { parameter: ethers.MaxUint256 } ];
        for (const variation of variations) {
          const cfg = config(input, state, c.parameter, variation);
          expect(await outcome(() => helper.measure(true, mode, state, input, cfg)))
            .to.deep.equal(await outcome(() => helper.measure(false, mode, state, input, cfg)));
        }
      }
    }
    const badKey = encodeBlock(Keys.Amount, blob(64));
    const badLength = encodeBlock(Keys.Balance, blob(63));
    for (const source of [balance, badKey, badLength, ethers.concat([badKey, "0xab"]),
      ethers.concat([balance, badKey, "0xab"]), ethers.concat([balance, "0xab"]),
      ethers.dataSlice(balance, 0, 71), "0x"]) {
      const cfg = config("0x", source);
      expect(await outcome(() => helper.measure(true, 19, source, "0x", cfg)))
        .to.deep.equal(await outcome(() => helper.measure(false, 19, source, "0x", cfg)));
    }
    for (const budget of [0n, 1n, 100n, ethers.MaxUint256]) {
      for (const parameter of [0n, 1n, 100n, ethers.MaxUint256]) {
        const cfg = config("0x", "0x", parameter, { budget });
        expect(await outcome(() => helper.measure(true, 21, "0x", "0x", cfg)))
          .to.deep.equal(await outcome(() => helper.measure(false, 21, "0x", "0x", cfg)));
      }
    }
  });
});
