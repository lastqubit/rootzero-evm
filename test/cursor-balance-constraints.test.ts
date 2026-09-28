import { expect } from "chai";
import { ethers } from "ethers";
import { deploy } from "./helpers/setup.js";
import { concat, encodeBalanceConstraintsBlock, encodeBlock, Keys } from "./helpers/blocks.js";
import { size } from "./helpers/cursor-consumers.js";

describe("CursorBlocks balance constraints", () => {
  let helper: any;
  const asset = ethers.toBeHex(1, 32), other = ethers.toBeHex(2, 32);
  before(async () => { helper = await deploy("TestCursorBalanceConstraints"); });
  for (const deferred of [false, true]) describe(deferred ? "validated payload check" : "checked cursor", () => {
    it("accepts inclusive full-width bounds and preserves source lanes", async () => {
      for (const [min, max, amount] of [[0n, 0n, 0n], [7n, 9n, 7n], [7n, 9n, 9n],
        [7n, 9n, 8n], [0n, ethers.MaxUint256, 1n << 200n], [ethers.MaxUint256, ethers.MaxUint256, ethers.MaxUint256]]) {
        const block = encodeBalanceConstraintsBlock(asset, min, max);
        const source = concat("0x123456", block, block);
        for (const metadata of [0n, ethers.MaxUint256]) {
          const [next, original] = await helper.check(source, 3, size(source), metadata, asset, amount, deferred);
          expect(next).eq(original + 104n);
        }
      }
    });
    it("rejects wrong assets and amounts including inverted ranges and literal zero maximum", async () => {
      for (const [min, max, actualAsset, amount, reason] of [
        [7n, 9n, other, 0n, "UnexpectedValue()"],
        [7n, 9n, asset, 6n, "OutOfRange()"], [7n, 9n, asset, 10n, "OutOfRange()"],
        [0n, 0n, asset, 1n, "OutOfRange()"], [9n, 7n, asset, 8n, "OutOfRange()"],
        [1n << 200n, ethers.MaxUint256, asset, (1n << 200n) - 1n, "OutOfRange()"],
      ] as const) {
        const block = encodeBalanceConstraintsBlock(asset, min, max);
        let error: unknown;
        try { await helper.check(block, 0, size(block), 0, actualAsset, amount, deferred); }
        catch (e: any) { error = e.data ?? e.info?.error?.data; }
        expect(error).eq(ethers.id(reason).slice(0, 10));
      }
    });
    it("establishes schema and containment before comparing values", async () => {
      const block = encodeBalanceConstraintsBlock(asset, 7n, 9n);
      const wrongKey = encodeBlock(Keys.Bytes, "0x" + "00".repeat(96));
      const wrongLength = encodeBlock(Keys.BalanceConstraints, "0x" + "00".repeat(95));
      for (const [source, offset, length, reason] of [
        ...[0, 1, 7, 8, 103].map(n => [block, 0, n, "OutOfBounds()"] as const),
        [concat("0xff", block), 1, 0, "OutOfBounds()"],
        [wrongKey, 0, 1, "InvalidBlock()"], [wrongLength, 0, size(wrongLength), "InvalidBlock()"],
      ] as const) {
        let error: unknown;
        try { await helper.check(source, offset, length, 0, other, 0n, deferred); }
        catch (e: any) { error = e.data ?? e.info?.error?.data; }
        expect(error).eq(ethers.id(reason).slice(0, 10));
      }
    });
  });
  it("chains checked constraints through returned cursors", async () => {
    const block = encodeBalanceConstraintsBlock(asset, 7n, 9n);
    expect(await helper.scan(concat(block, block, block), asset, 8n)).eq(3n);
  });
});
