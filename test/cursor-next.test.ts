import { expect } from "chai";
import { ethers } from "ethers";
import { deploy } from "./helpers/setup.js";
import { concat, encodeBlock, Keys } from "./helpers/blocks.js";
const invalid = ethers.id("InvalidBlock()").slice(0, 10), bounds = ethers.id("OutOfBounds()").slice(0, 10);
const size = (s: string) => ethers.getBytes(s).length;
const words = concat(ethers.toBeHex(ethers.MaxUint256, 32), ethers.toBeHex(7, 32));
const balance = encodeBlock(Keys.Balance, words);
const step = (data: string) => encodeBlock(Keys.Step, concat(words, encodeBlock(Keys.Input, data)));
async function errorOf(call: Promise<any>) {
  try { await call; return undefined; }
  catch(e: any) { const data = e.data ?? e.info?.error?.data; if (typeof data !== "string") throw e; return data; }
}
describe("Unpackers returning the advanced source cursor", function () {
  this.timeout(120_000);
  for (const kind of ["Balance", "Step"]) for (const variant of ["Selected", "Composed", "Direct", "Current", "Absolute"]) describe(`${kind}/${variant}`, () => {
    let helper: any;
    before(async () => { helper = await deploy(`CursorNext${kind}${variant}`); });
    it("preserves the source end and every metadata lane while consuming exactly one block", async () => {
      for (const length of kind === "Step" ? [0, 1, 31, 32, 33, 256] : [0]) {
        const data = "0x" + "ab".repeat(length), block = kind === "Step" ? step(data) : balance;
        for (const metadata of [0n, 0xa5n << 64n, ethers.MaxUint256 & ~((1n << 64n) - 1n)]) {
          const source = concat("0x123456", block, block);
          for (const limit of [3 + size(block), size(source)]) {
            const r = await helper.inspect(source, limit, 3, metadata);
            const nextCur = kind === "Step" ? r[3] : r[2], originalCur = kind === "Step" ? r[4] : r[3], baseAbs = kind === "Step" ? r[5] : r[4];
            expect(kind === "Step" ? r[0] : BigInt(r[0])).eq(ethers.MaxUint256); expect(r[1]).eq(7n);
            expect(nextCur & 0xffffffffn).eq(baseAbs + BigInt(3 + size(block)));
            expect(nextCur >> 32n).eq(originalCur >> 32n);
            expect(nextCur >> 64n).eq(metadata >> 64n);
            if (kind === "Step") {
              expect(r[2]).eq((baseAbs + 83n) | ((baseAbs + BigInt(3 + size(block))) << 32n));
              expect(r[2] >> 64n).eq(0n); expect(r[6]).eq(data);
            }
          }
        }
      }
    });
    it("retains bounds checks even when nextCur and child cursors are discarded", async () => {
      const block = kind === "Step" ? step("0x123456") : balance;
      for (const length of [0, 7, 8, 39, size(block) - 1]) expect(await errorOf(helper.inspect(block, length, 0, ethers.MaxUint256))).eq(bounds);
      expect(await errorOf(helper.inspect(concat("0x123456", block), 2, 3, 0))).eq(bounds);
      expect(await errorOf(helper.onlyValues(ethers.dataSlice(block, 0, size(block) - 1)))).eq(bounds);
    });
    it("preserves shape errors and rejects malformed dynamic children", async () => {
      const bad = encodeBlock(Keys.String, words);
      expect(await errorOf(helper.inspect(bad, 0, 0, 0))).eq(invalid);
      const cases = kind === "Balance"
        ? [encodeBlock(Keys.Balance, "0x"), encodeBlock(Keys.Balance, concat(words, "0xff"))]
        : [encodeBlock(Keys.Step, words), encodeBlock(Keys.Step, concat(words, encodeBlock(Keys.String, "0x"))),
          encodeBlock(Keys.Step, concat(words, Keys.Input, "0xffffffff")), encodeBlock(Keys.Step, concat(words, encodeBlock(Keys.Input, "0x"), "0xff"))];
      for (const source of cases) {
        expect(await errorOf(helper.inspect(source, size(source), 0, 0))).eq(invalid);
        expect(await errorOf(helper.onlyValues(source))).eq(invalid);
      }
    });
    it("advances correctly through mixed payload sizes", async () => {
      const source = kind === "Balance" ? concat(balance, balance, balance) : concat(step("0x"), step("0x12"), step("0x" + "ab".repeat(33)));
      const baseline = await deploy(`CursorNext${kind}Selected`);
      const expected = await baseline.measure(source), actual = await helper.measure(source);
      expect(actual[1]).eq(expected[1]); expect(actual[2]).eq(expected[2]);
      expect(actual[2] & 0xffffffffn).eq((actual[2] >> 32n) & 0xffffffffn);
    });
  });
});
