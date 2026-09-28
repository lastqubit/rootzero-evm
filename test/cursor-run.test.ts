import { expect } from "chai";
import { ethers } from "ethers";
import { deploy } from "./helpers/setup.js";
import { concat, encodeBlock, Keys } from "./helpers/blocks.js";

const size = (s: string) => ethers.getBytes(s).length;
describe("Cursor count-only run hints", function () {
  this.timeout(120_000);
  for (const variant of ["Baseline", "Composed", "Fused", "Current"]) describe(variant, () => {
    let helper: any;
    before(async () => { helper = await deploy(`CursorRun${variant}`); });
    it("counts consecutive matching blocks, including empty and unaligned payloads", async () => {
      for (const key of [Keys.Bytes, "0x00000000", "0xffffffff"]) {
        const blocks = [0, 1, 31, 32, 33, 256].map(n => encodeBlock(key, "0x" + "ab".repeat(n)));
        const run = concat(...blocks), different = encodeBlock(Keys.String, "0x12");
        for (const tail of ["0x", different, concat(different, blocks[0])]) {
          const source = concat("0x123456", run, tail);
          for (const metadata of [0n, 0xa5n << 64n, ethers.MaxUint256]) {
            expect(await helper.inspect(source, size(source), 3, metadata, key)).eq(6n);
          }
        }
      }
    });
    it("returns zero for empty, reversed, and immediately nonmatching ranges", async () => {
      const block = encodeBlock(Keys.Bytes, "0x");
      expect(await helper.inspect("0x", 0, 0, ethers.MaxUint256, Keys.Bytes)).eq(0n);
      expect(await helper.inspect(block, 0, 1, 0, Keys.Bytes)).eq(0n);
      expect(await helper.inspect(block, 8, 8, 0, Keys.Bytes)).eq(0n);
      expect(await helper.inspect(block, 8, 0, 0, Keys.String)).eq(0n);
    });
    it("stops without reverting on a partial header, payload, or oversized length", async () => {
      const block = encodeBlock(Keys.Bytes, "0x123456"), first = encodeBlock(Keys.Bytes, "0x");
      for (let length = 0; length < size(block); length++) {
        // Physical bytes after the logical boundary must not make a block count.
        const source = concat(first, block, block);
        expect(await helper.inspect(source, 8 + length, 0, 0, Keys.Bytes)).eq(1n);
        expect(await helper.inspect(ethers.dataSlice(source, 0, 8 + length), 8 + length, 0, 0, Keys.Bytes)).eq(1n);
      }
      for (const key of [Keys.Bytes, Keys.String]) {
        const source = concat(first, key, "0xffffffff", block);
        expect(await helper.inspect(source, size(source), 0, 0, Keys.Bytes)).eq(1n);
      }
      // Zero-padding a zero-key partial header must not invent a complete block.
      expect(await helper.inspect("0x00000000", 4, 0, 0, "0x00000000")).eq(0n);
    });
    it("keeps computed ends full-width near the uint32 boundary", async () => {
      const end = 0xffffffffn;
      expect(await helper.raw((end - 3n) | (end << 32n), "0x00000000")).eq(0n);
      expect(await helper.raw(end | ((end - 1n) << 32n), "0x00000000")).eq(0n);
    });
    it("matches a host-side hint scan across mixed keys, lengths, and truncations", async () => {
      let seed = 12345;
      const random = () => { seed = (Math.imul(seed, 1664525) + 1013904223) >>> 0; return seed; };
      for (let i = 0; i < 40; i++) {
        const blocks = Array.from({ length: 1 + random() % 8 }, () => encodeBlock(random() % 4 ? Keys.Bytes : Keys.String, "0x" + "ab".repeat(random() % 34)));
        const source = concat(...blocks), length = random() % (size(source) + 1);
        let abs = 0, expected = 0;
        for (const block of blocks) {
          if (abs >= length || ethers.dataSlice(block, 0, 4) !== Keys.Bytes || abs + size(block) > length) break;
          abs += size(block); expected++;
        }
        expect(await helper.inspect(source, length, 0, ethers.MaxUint256, Keys.Bytes)).eq(BigInt(expected));
      }
    });
  });
});
