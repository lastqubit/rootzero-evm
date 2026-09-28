import { expect } from "chai";
import { ethers } from "ethers";
import { deploy } from "./helpers/setup.js";
import { concat, encodeBlock, encodePositionConstraintsBlock, Keys } from "./helpers/blocks.js";

describe("Deferred constraint payload checking", () => {
  const word = (v: bigint) => ethers.toBeHex(v, 32);
  for (const variant of ["Current", "Values"]) describe(variant, () => {
    let helper: any;
    before(async () => { helper = await deploy(`CursorDeferredConstraint${variant}`); });
    it("checks saved unaligned payloads against later position values", async () => {
      for (const [min, max, amount, debt] of [[7n, 3n, 7n, 3n], [7n, 3n, 8n, 2n], [0n, 0n, 0n, 0n],
        [ethers.MaxUint256, ethers.MaxUint256, ethers.MaxUint256, ethers.MaxUint256]]) {
        const block = encodePositionConstraintsBlock(word(1n), min, word(2n), max);
        const source = concat("0xff", block, "0x123456", block);
        const r = await helper.measure(source, [1, 140], [136, 136], [word(1n), amount, word(2n), debt, word(99n)], false);
        expect(r[1]).eq(2n);
      }
    });
    it("preserves identifier-before-quantity errors and full-width comparisons", async () => {
      const block = encodePositionConstraintsBlock(word(1n), 7n, word(2n), 3n);
      for (const [asset, amount, liability, debt, reason] of [
        [3n, 0n, 2n, ethers.MaxUint256, "UnexpectedValue()"],
        [1n, 7n, 3n, 3n, "UnexpectedValue()"],
        [1n, 6n, 2n, 3n, "OutOfRange()"],
        [1n, 7n, 2n, 1n << 128n, "OutOfRange()"],
      ] as const) {
        let error: unknown;
        try { await helper.measure(block, [0], [136], [word(asset), amount, word(liability), debt, word(0n)], false); }
        catch (e: any) { error = e.data ?? e.info?.error?.data; }
        expect(error).eq(ethers.id(reason).slice(0, 10));
      }
    });
    it("establishes header and containment validation before saving a payload", async () => {
      const valid = encodePositionConstraintsBlock(word(1n), 7n, word(2n), 3n);
      for (const [source, length, reason] of [[valid, 135, "OutOfBounds()"],
        [encodeBlock(Keys.Bytes, "0x" + "00".repeat(128)), 136, "InvalidBlock()"]] as const) {
        let error: unknown;
        try { await helper.measure(source, [0], [length], [word(1n), 7n, word(2n), 3n, word(0n)], false); }
        catch (e: any) { error = e.data ?? e.info?.error?.data; }
        expect(error).eq(ethers.id(reason).slice(0, 10));
      }
    });
  });
});
