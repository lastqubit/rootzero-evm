import { expect } from "chai";
import { ethers } from "ethers";
import { deploy } from "./helpers/setup.js";
import { concat, encodeBlock, Keys } from "./helpers/blocks.js";
const invalid = ethers.id("InvalidBlock()").slice(0, 10), bounds = ethers.id("OutOfBounds()").slice(0, 10);
async function errorOf(call: Promise<any>) { try {
  await call;
  return undefined;
}
catch (e: any) {
  const d = e.data ?? e.info?.error?.data;
  if (typeof d !== "string")
    throw e;
  return d;
} }
describe("Cursor five-word unpacking", function () {
  for (const variant of ["Baseline", "Composed", "Fused", "RangeReference"])
    describe(variant, () => {
      let h: any;
      before(async () => { h = await deploy(`CursorWide${variant}`); });
      it("returns all five full-width words and a clean bounded block cursor", async () => {
        for (const key of [Keys.Position, Keys.Bytes]) {
          const words = [0n, ethers.MaxUint256, 1n, 1n << 255n, 12345n].map(x => ethers.toBeHex(x, 32));
          const block = encodeBlock(key, concat(...words)), source = concat("0x123456", block, block);
          const r = await h.inspect(source, 339, 3, key);
          expect(Array.from(r).slice(0, 5)).deep.eq(words);
          expect(r[5]).eq((r[6] + 3n) | ((r[6] + 171n) << 32n));
        }
      });
      it("rejects truncation, incorrect keys and widths, and reversed ranges", async () => {
        const block = encodeBlock(Keys.Position, "0x" + "ab".repeat(160));
        for (const length of [0, 7, 8, 39, 71, 103, 135, 167])
          expect(await errorOf(h.inspect(block, length, 0, Keys.Position))).eq(bounds);
        expect(await errorOf(h.inspect(concat("0x123456", block), 2, 3, Keys.Position))).eq(bounds);
        for (const length of [0, 32, 128, 159, 161]) {
          const bad = encodeBlock(Keys.Position, "0x" + "ab".repeat(length));
          expect(await errorOf(h.inspect(bad, length + 8, 0, Keys.Position))).eq(invalid);
        }
        expect(await errorOf(h.inspect(block, 0, 0, Keys.Bytes))).eq(invalid);
        expect(await errorOf(h.inspect(concat(Keys.Position, "0xffffffff"), 8, 0, Keys.Position))).eq(invalid);
      });
      it("retains validation when the block cursor is discarded", async () => {
        const bad = concat(Keys.Position, "0x000000a0", "0x" + "ab".repeat(159));
        expect(await errorOf(h.measureValues(bad, Keys.Position))).eq(bounds);
      });
    });
});
