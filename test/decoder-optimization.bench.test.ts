import { expect } from "chai";
import { ethers } from "ethers";
import { mkdirSync, writeFileSync } from "node:fs";
import { deploy } from "./helpers/setup.js";
import { encodeBlock, encodeBytesBlock, encodeStepBlock, encodeCallBlock, encodeContextBlock,
  encodeRelayBlock, encodeDispatchBlock, encodeRecoverBlock, encodeLabelBlock,
  encodeSchemaBlock, encodeAnnotationBlock, Keys, exactSpec, rangedSpec } from "./helpers/blocks.js";

const word = ethers.toBeHex(33, 32);
const blob = (size: number) => "0x" + "ab".repeat(size);
const supported = [
  { name: "unpackBytes", input: encodeBytesBlock(blob(3)), parameter: 0n },
  { name: "unpackStep", input: encodeStepBlock(11n, 22n, blob(3)), parameter: 0n },
  { name: "consumeSpec", input: encodeBytesBlock(blob(3)), parameter: rangedSpec(Keys.Bytes, 0, 0, 0) },
  { name: "consumeKey", input: encodeBytesBlock(blob(3)), parameter: BigInt(Keys.Bytes) },
  { name: "unpackRaw", input: encodeBytesBlock(blob(3)), parameter: rangedSpec(Keys.Bytes, 0, 0, 0) },
  { name: "unpackString", input: encodeBlock(Keys.String, blob(3)), parameter: 0n },
  { name: "unpackContext", input: encodeContextBlock(word, blob(3), blob(5)), parameter: 0n },
  { name: "unpackRelay", input: encodeRelayBlock(blob(3), blob(5)), parameter: 0n },
  { name: "unpackLabel", input: encodeLabelBlock(word, "abc"), parameter: 0n },
  { name: "unpackSchema", input: encodeSchemaBlock(11n, "abc", word), parameter: 0n },
  { name: "unpackRecover", input: encodeRecoverBlock(11n, 22n, word, blob(3)), parameter: 0n },
  { name: "unpackCall", input: encodeCallBlock(11n, 22n, blob(3)), parameter: 0n },
  { name: "unpackDispatch", input: encodeDispatchBlock(11n, 22n, blob(3)), parameter: 0n },
  { name: "unpackAnnotation", input: encodeAnnotationBlock(11n, blob(3)), parameter: 0n },
  { name: "tryConsumeEmpty", input: encodeBytesBlock("0x"), parameter: BigInt(Keys.Bytes) },
  { name: "unpack32", input: encodeBlock(Keys.Bytes, blob(32)), parameter: exactSpec(Keys.Bytes, 32) },
];
function config(input: string, parameter: bigint, extra: object = {}) {
  return { start: 0, end: ethers.dataLength(input), flags: 0x5an, parameter, repetitions: 1, ...extra };
}
async function outcome(call: () => Promise<any>) {
  try { const r = await call(); return { state: r.state, data: r.data }; }
  catch (error: any) {
    const data = error.data ?? error.info?.error?.data;
    if (typeof data !== "string") throw error;
    return { error: data };
  }
}
describe("Decoder cursor optimization", function () {
  this.timeout(180_000);
  it("benchmarks every affected decoder with identical values and cursor metadata", async () => {
    const helper = await deploy("TestDecoderOptimization");
    const rows: object[] = [];
    for (let mode = 0; mode < supported.length; mode++) {
      const c = supported[mode];
      for (const count of [1, 8]) {
        const input = ethers.concat(Array(count).fill(c.input));
        const cfg = config(input, c.parameter, { repetitions: count });
        const before = await helper.measure(false, mode, input, cfg);
        const after = await helper.measure(true, mode, input, cfg);
        expect(after.state).to.equal(before.state);
        expect(after.data).to.equal(before.data);
        expect(after.usedGas, c.name).to.be.lessThan(before.usedGas);
        rows.push({ operation: c.name, count, before: Number(before.usedGas), after: Number(after.usedGas),
          saved: Number(before.usedGas - after.usedGas) });
      }
    }
    mkdirSync(".npm-cache", { recursive: true });
    writeFileSync(".npm-cache/decoder-results.json", JSON.stringify(rows, null, 2) + "\n");
    console.table(rows);
  });
  it("preserves validation errors, partial consumption, high flags, and forged bounds", async () => {
    const helper = await deploy("TestDecoderOptimization");
    for (let mode = 0; mode < supported.length; mode++) {
      const c = supported[mode];
      const samples = [c.input, "0x", "0xffffffff", ethers.dataSlice(c.input, 0, Math.min(7, ethers.dataLength(c.input))),
        ethers.concat([c.input, "0xab"]), ethers.concat([Keys.Bytes, "0xffffffff"])];
      for (const input of samples) {
        const len = ethers.dataLength(input);
        const variants = [{}, { end: Math.max(0, len - 1) }, { start: len + 1 },
          { end: 65536 }, { flags: (1n << 192n) - 1n }, { parameter: 0n }, { parameter: ethers.MaxUint256 },
          { start: 0xfffff000, end: 0xfffff008, parameter: 0n }];
        for (const extra of variants) {
          // Huge returned slices would make ABI copying exhaust gas in both fixtures;
          // invalid keys/lengths and logical bounds still get exercised here.
          const cfg = config(input, c.parameter, extra);
          expect(await outcome(() => helper.measure(true, mode, input, cfg)))
            .to.deep.equal(await outcome(() => helper.measure(false, mode, input, cfg)));
        }
      }
    }
  });
});
