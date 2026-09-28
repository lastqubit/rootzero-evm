import { expect } from "chai";
import { ethers } from "ethers";
import { deploy } from "./helpers/setup.js";
import { concat, encodeBlock, encodePositionConstraintsBlock, Keys } from "./helpers/blocks.js";
const selector = (name: string) => ethers.id(`${name}()`).slice(0, 10);
const invalid = selector("InvalidBlock"), bounds = selector("OutOfBounds"), mismatch = selector("UnexpectedValue"), outside = selector("OutOfRange");
const asset = ethers.toBeHex(1, 32), liability = ethers.toBeHex(2, 32), other = ethers.toBeHex(3, 32);
const max = ethers.MaxUint256;
async function errorOf(call: Promise<any>) {
  try { await call; return undefined; }
  catch (e: any) { const data = e.data ?? e.info?.error?.data; if (typeof data !== "string") throw e; return data; }
}
describe("Cursor position-constraint expectations", function () {
  this.timeout(120_000);
  for (const variant of ["Baseline", "Readable", "Packed", "Grouped", "Fused", "Decoded", "ReadCompare", "Current"]) describe(variant, () => {
    let helper: any;
    before(async () => { helper = await deploy(`CursorExpect${variant}`); });
    it("accepts equality, better outcomes and full-width bounds without changing the position", async () => {
      for (const [minimum, maximum, amount, debt] of [
        [0n, 0n, 0n, 0n], [0n, 0n, max, 0n], [123n, 456n, 123n, 456n], [123n, 456n, 124n, 455n],
        [1n << 128n, (1n << 128n) + 1n, 1n << 128n, (1n << 128n) + 1n], [max, max, max, max],
      ]) for (const counterparty of [ethers.ZeroHash, other]) {
        const block = encodePositionConstraintsBlock(asset, minimum, liability, maximum);
        const position = [asset, amount, liability, debt, counterparty];
        const r = await helper.inspect(concat("0x123456", block, block), 275, 3, position);
        const expected = variant === "Current"
          ? (r[1] + 139n) | ((r[1] + 275n) << 32n) | (0xabcdefn << 64n)
          : (r[1] + 3n) | ((r[1] + 139n) << 32n);
        expect(r[0]).eq(expected);
        expect(Array.from(r[2])).deep.eq(position);
      }
      const zero = encodePositionConstraintsBlock(ethers.ZeroHash, 0n, ethers.ZeroHash, 0n);
      await helper.onlyCheck(zero, [ethers.ZeroHash, 0, ethers.ZeroHash, 0, other]);
    });
    if (variant === "Current") it("advances one block while preserving the full source end and metadata", async () => {
      const block = encodePositionConstraintsBlock(asset, 123n, liability, 456n);
      const position = [asset, 123n, liability, 456n, other];
      const source = concat("0x123456", block, block);
      for (const metadata of [0n, 0xa5n << 64n, max]) for (const length of [139, 275]) {
        const r = await helper.inspectMetadata(source, length, 3, metadata, position);
        expect(r[0] & 0xffffffffn).eq(r[2] + 139n);
        expect(r[0] >> 32n).eq(r[1] >> 32n);
        expect(r[0] >> 64n).eq(metadata >> 64n);
      }
      const r = await helper.measure(concat(block, block, block), position);
      expect(r[1]).eq(3n);
      expect(r[2] & 0xffffffffn).eq((r[2] >> 32n) & 0xffffffffn);
      expect(r[2] >> 64n).eq(0xa5n);
    });
    it("rejects either identifier mismatch before quantity errors", async () => {
      const block = encodePositionConstraintsBlock(asset, 123n, liability, 456n);
      for (const position of [[other, 0, liability, max, other], [asset, 0, other, max, other], [other, 0, other, max, other]]) {
        expect(await errorOf(helper.inspect(block, 136, 0, position))).eq(mismatch);
        expect(await errorOf(helper.onlyCheck(block, position))).eq(mismatch);
      }
    });
    it("enforces inclusive full-width quantities and literal zero maximum debt", async () => {
      for (const [minimum, maximum, amount, debt] of [
        [123n, 456n, 122n, 456n], [123n, 456n, 123n, 457n], [123n, 456n, 122n, 457n],
        [0n, 0n, 0n, 1n], [1n << 128n, max, (1n << 128n) - 1n, 0n],
        [0n, 1n << 128n, 0n, (1n << 128n) + 1n], [max, max, max - 1n, 0n], [0n, max - 1n, 0n, max],
      ]) {
        const block = encodePositionConstraintsBlock(asset, minimum, liability, maximum), position = [asset, amount, liability, debt, other];
        expect(await errorOf(helper.inspect(block, 136, 0, position))).eq(outside);
        expect(await errorOf(helper.onlyCheck(block, position))).eq(outside);
      }
    });
    it("bounds the full block before value checks, including reversed ranges", async () => {
      const block = encodePositionConstraintsBlock(asset, 123n, liability, 456n), position = [other, 0, other, max, other];
      for (const length of [0, 7, 8, 39, 40, 71, 72, 103, 104, 135]) {
        expect(await errorOf(helper.inspect(block, length, 0, position))).eq(bounds);
      }
      expect(await errorOf(helper.inspect(concat("0x123456", block), 2, 3, position))).eq(bounds);
      expect(await errorOf(helper.onlyCheck(ethers.dataSlice(block, 0, 135), position))).eq(bounds);
      expect(await errorOf(helper.measureDiscard(ethers.dataSlice(block, 0, 135), position))).eq(bounds);
    });
    it("rejects wrong keys and lengths before checking identifiers", async () => {
      const position = [other, 0, other, max, other];
      for (const [key, length] of [[Keys.Bytes, 128], [Keys.PositionConstraints, 0], [Keys.PositionConstraints, 127], [Keys.PositionConstraints, 129], [Keys.PositionConstraints, 0xffffffff]] as const) {
        const source = concat(key, ethers.toBeHex(length, 4), "0x" + "ff".repeat(128));
        expect(await errorOf(helper.inspect(source, 136, 0, position))).eq(invalid);
        if (variant !== "Baseline" && variant !== "Decoded") expect(await errorOf(helper.inspect(source, 0, 0, position))).eq(invalid);
      }
    });
    it("matches independent predicates across deterministic mixed cases", async () => {
      let seed = 123456789n;
      const random = () => { seed = (seed * 6364136223846793005n + 1442695040888963407n) & max; return seed; };
      for (let i = 0; i < 32; ++i) {
        const minimum = random(), maximum = random(), amount = i % 3 === 0 ? minimum : random(), debt = i % 4 === 0 ? maximum : random();
        const actualAsset = i % 7 === 0 ? other : asset, actualLiability = i % 11 === 0 ? other : liability;
        const expected = actualAsset !== asset || actualLiability !== liability ? mismatch : amount < minimum || debt > maximum ? outside : undefined;
        expect(await errorOf(helper.onlyCheck(encodePositionConstraintsBlock(asset, minimum, liability, maximum), [actualAsset, amount, actualLiability, debt, other]))).eq(expected);
      }
    });
  });
});
