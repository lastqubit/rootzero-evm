import { expect } from "chai";
import { ethers } from "ethers";
import { deploy } from "./helpers/setup.js";
import { concat, encodeBlock, Keys } from "./helpers/blocks.js";

const invalid = ethers.id("InvalidBlock()").slice(0, 10);
const bounds = ethers.id("OutOfBounds()").slice(0, 10);
const unpackVariants = ["Baseline", "Composed", "Fused", "End", "BalanceBaseline", "BalanceComposed", "BalanceFused", "BalanceDirect", "RangeReference", "BalanceRangeReference", "FusedReference", "BalanceFusedReference"];
async function outcome(call: () => Promise<any>) {
  try { return { value: Array.from(await call()) }; }
  catch (error: any) {
    const data = error.data ?? error.info?.error?.data;
    if (typeof data !== "string") throw error;
    return { error: data };
  }
}

describe("Cursor unpack candidates", function () {
  this.timeout(120_000);
  for (const variant of unpackVariants) describe(variant, () => {
    let helper: any;
    before(async () => { helper = await deploy(`CursorUnpack${variant}`); });
    it("decodes both full-width fields and returns a clean block cursor at nonzero offsets", async () => {
      for (const [a, b] of [[0n, 0n], [ethers.MaxUint256, 1n], [1n, ethers.MaxUint256]]) {
        const block = encodeBlock(Keys.Balance, concat(ethers.toBeHex(a, 32), ethers.toBeHex(b, 32)));
        const source = concat("0x123456", block, block);
        const result = await helper.inspect(source, 147, 3, Keys.Balance);
        expect(result[0]).eq(ethers.toBeHex(a, 32));
        expect(result[1]).eq(ethers.toBeHex(b, 32));
        expect(result[2]).eq((result[3] + 3n) | ((result[3] + 75n) << 32n));
      }
      if (!variant.startsWith("Balance")) {
        const source = encodeBlock(Keys.Bytes, "0x" + "ff".repeat(64));
        const result = await helper.inspect(source, 72, 0, Keys.Bytes);
        expect(result[0]).eq(ethers.toBeHex(ethers.MaxUint256, 32));
      }
      const reversed = concat("0x123456", encodeBlock(Keys.Balance, "0x" + "ab".repeat(64)));
      expect((await outcome(() => helper.inspect(reversed, 2, 3, Keys.Balance))).error).eq(bounds);
    });
    it("rejects truncated logical ranges, wrong shapes, and oversized declared payloads", async () => {
      const source = encodeBlock(Keys.Balance, "0x" + "ab".repeat(64));
      for (const length of [0, 7, 8, 39, 40, 71]) {
        expect((await outcome(() => helper.inspect(source, length, 0, Keys.Balance))).error).eq(bounds);
      }
      for (const length of [0, 32, 63, 65]) {
        const wrong = encodeBlock(Keys.Balance, "0x" + "ab".repeat(length));
        expect((await outcome(() => helper.inspect(wrong, length + 8, 0, Keys.Balance))).error).eq(invalid);
      }
      const wrongKey = encodeBlock(Keys.Bytes, "0x" + "ab".repeat(64));
      // Shape error precedes bounds error even when both are wrong.
      expect((await outcome(() => helper.inspect(wrongKey, 0, 0, Keys.Balance))).error).eq(invalid);
      const huge = concat(Keys.Balance, "0xffffffff");
      expect((await outcome(() => helper.inspect(huge, 8, 0, Keys.Balance))).error).eq(invalid);
    });
    it("keeps validation when the caller discards the returned cursor", async () => {
      const bad = concat(Keys.Balance, "0x00000040", "0x" + "ab".repeat(32));
      expect((await outcome(() => helper.measureValues(bad, Keys.Balance))).error).eq(bounds);
    });
  });
});
