import { expect } from "chai";
import { ethers } from "ethers";
import { deploy } from "./helpers/setup.js";
import { concat, encodeBlock, exactSpec, rangedSpec, Keys } from "./helpers/blocks.js";

const INVALID = ethers.id("InvalidBlock()").slice(0, 10);
const BOUNDS = ethers.id("OutOfBounds()").slice(0, 10);
const metadata = 0x3123456789abcdef01n;
const modes = ["take", "spec", "key", "fixed", "enterSpec", "enterKey", "prefixSpec", "prefixKey", "exact"];
async function outcome(call: () => Promise<any>) {
  try { return { value: Array.from(await call()) }; }
  catch (error: any) {
    const data = error.data ?? error.info?.error?.data;
    if (typeof data !== "string") throw error;
    return { error: data };
  }
}

for (const contract of ["TestCursorBlocks", "TestCursorEntryCandidates", "TestFusedCursorBlocks"]) describe(contract, function () {
  this.timeout(120_000);
  let helper: any;
  before(async () => { helper = await deploy(contract); });

  for (const [mode, name] of modes.entries()) {
    it(`${name} returns the expected bounded range and preserves the stream metadata`, async () => {
      for (const length of [0, 1, 7, 32, 64, 208]) {
        const block = encodeBlock(Keys.Bytes, "0x" + "ab".repeat(length));
        const prefix = encodeBlock(Keys.String, "0x1234");
        const offset = ethers.dataLength(prefix);
        const input = concat(prefix, block);
        const amount = Math.floor(length / 2);
        const args = [input, ethers.dataLength(input), offset, exactSpec(Keys.Bytes, length), amount, mode];
        const old = await helper.inspect(...args, false);
        const next = await helper.inspect(...args, true);
        expect(Array.from(next)).to.deep.equal(Array.from(old));
        const [cur, base, stream] = next;
        const start = base + BigInt(offset + (mode >= 4 ? 8 : 0) + (mode === 6 || mode === 7 ? amount : 0));
        const end = base + BigInt(offset + length + 8);
        expect(cur).to.equal(start | (end << 32n));
        expect(cur >> 64n).to.equal(0n);
        expect(stream & 0xffffffffn).to.equal(end);
        expect((stream >> 32n) & 0xffffffffn).to.equal(base + BigInt(ethers.dataLength(input)));
        expect(stream >> 64n).to.equal(metadata);
      }
    });

    it(`${name} rejects logical truncation even with valid bytes after the boundary`, async () => {
      const length = 32;
      const input = encodeBlock(Keys.Bytes, "0x" + "ab".repeat(length));
      for (const logicalLength of [...new Set([0, 1, 7, length + 7])]) {
        const args = [input, logicalLength, 0, exactSpec(Keys.Bytes, length), 0, mode];
        const result = await outcome(() => helper.inspect(...args, true));
        expect(result.error).to.equal(mode === 8 ? INVALID : BOUNDS);
        if (mode !== 0) expect(result).to.deep.equal(await outcome(() => helper.inspect(...args, false)));
      }
    });
  }

  it("selects one block without absorbing trailing blocks, while exact rejects them", async () => {
    const block = encodeBlock(Keys.Bytes, "0x" + "ab".repeat(32));
    const input = concat(block, block);
    for (const mode of [0, 1, 2, 3, 4, 5, 6, 7]) {
      const [cur, base, stream] = await helper.inspect(input, 80, 0, exactSpec(Keys.Bytes, 32), 0, mode, true);
      expect(cur >> 32n).to.equal(base + 40n);
      expect((stream >> 32n) & 0xffffffffn).to.equal(base + 80n);
    }
    expect((await outcome(() => helper.inspect(input, 80, 0, exactSpec(Keys.Bytes, 32), 0, 8, true))).error).eq(INVALID);
  });

  it("enforces schema limits, exact headers", async () => {
    const input = encodeBlock(Keys.Bytes, "0x" + "ab".repeat(32));
    const specs = [
      [rangedSpec(Keys.Bytes, 16, 64, 0), true],
      [rangedSpec(Keys.Bytes, 32, 0, 0), true],
      [rangedSpec(Keys.Bytes, 33, 0, 0), false],
      [rangedSpec(Keys.Bytes, 0, 31, 0), false],
      [exactSpec(Keys.String, 32), false],
    ] as const;
    for (const mode of [1, 4, 6, 8]) for (const [spec, valid] of specs) {
      const args = [input, 40, 0, spec, 0, mode];
      const result = await outcome(() => helper.inspect(...args, true));
      expect(result.error).eq(valid ? undefined : INVALID);
      expect(result).deep.eq(await outcome(() => helper.inspect(...args, false)));
    }
    for (const mode of [2, 3, 5, 7]) {
      expect((await outcome(() => helper.inspect(input, 40, 0, exactSpec(Keys.String, 32), 0, mode, true))).error).eq(INVALID);
    }
    expect((await outcome(() => helper.inspect(input, 40, 0, exactSpec(Keys.Bytes, 31), 0, 3, true))).error).eq(INVALID);
  });

  it("checks prefixes once, allows an empty remainder, and rejects oversized amounts", async () => {
    const input = encodeBlock(Keys.Bytes, "0x" + "ab".repeat(32));
    for (const mode of [6, 7]) for (const amount of [0n, 31n, 32n, 33n, ethers.MaxUint256]) {
      const args = [input, 40, 0, exactSpec(Keys.Bytes, 32), amount, mode];
      const result = await outcome(() => helper.inspect(...args, true));
      expect(result.error).eq(amount > 32n ? INVALID : undefined);
      expect(result).deep.eq(await outcome(() => helper.inspect(...args, false)));
      if (amount === 32n) {
        const cur = result.value![0] as bigint;
        expect(cur & 0xffffffffn).eq(cur >> 32n);
      }
    }
  });

  it("rejects reversed ranges and full-width ends before packing", async () => {
    const input = encodeBlock(Keys.Bytes, "0x");
    for (const mode of modes.keys()) {
      expect((await outcome(() => helper.inspect(input, 0, 0, exactSpec(Keys.Bytes, 0), 0, mode, true))).error).eq(mode === 8 ? INVALID : BOUNDS);
      const cur = 0xfffffffcn | (0xffffffffn << 32n);
      const result = await outcome(async () => [await helper.raw(cur, 0, 0, mode)]);
      expect(result.error).eq(mode === 8 ? INVALID : BOUNDS);
      const reversed = await outcome(() => helper.inspect(input, 0, 1, exactSpec(Keys.Bytes, 0), 0, mode, true));
      expect(reversed.error).to.be.a("string");
    }
    const huge = concat(Keys.Bytes, "0xffffffff");
    for (const mode of [0, 1, 2, 4, 5]) {
      expect((await outcome(() => helper.inspect(huge, 8, 0, rangedSpec(Keys.Bytes, 0, 0, 0), 0, mode, true))).error).eq(BOUNDS);
    }
  });

  it("bounds a nested child by its parent payload rather than the outer calldata", async () => {
    const child = encodeBlock(Keys.Bytes, "0x" + "ab".repeat(32));
    const good = encodeBlock(Keys.List, child);
    const [parent, selected] = await helper.nested(good, exactSpec(Keys.List, 40), exactSpec(Keys.Bytes, 32));
    expect(selected).eq(parent);
    const bad = concat(Keys.List, "0x00000008", child);
    expect((await outcome(() => helper.nested(bad, exactSpec(Keys.List, 8), exactSpec(Keys.Bytes, 32)))).error).eq(BOUNDS);
  });
});

describe("CursorBlocks raw reads", () => {
  it("exposes unchecked absolute reads with unaligned positions and EVM zero-padding", async () => {
    const helper = await deploy("TestCursorRead32");
    const source = "0x" + "1234567890abcdef".repeat(8);
    for (const offset of [0, 1, 7, 32]) {
      const result = await helper.readAt(source, offset);
      expect(result[0]).eq(ethers.dataSlice(source, offset, offset + 32));
      expect(result[0]).eq(result[1]);
    }
    const partial = await helper.readAt("0x123456", 0);
    expect(partial[0]).eq("0x123456" + "00".repeat(29));
    expect(partial[0]).eq(partial[1]);
    // A packed-cursor position mask would turn this into a nonzero read at byte 4.
    for (const abs of [(1n << 32n) + 4n, ethers.MaxUint256]) {
      expect(await helper.readAbsolute(abs)).eq(ethers.ZeroHash);
    }
  });
});


describe("CursorBlocks.takeExact", () => {
  it("returns a clean complete block and shares unpackExact validation", async () => {
    const take = await deploy("TestCursorTakeExact");
    const unpack = await deploy("TestCursorBlocks");
    for (const length of [0, 1, 32, 65]) {
      const block = encodeBlock(Keys.Bytes, "0x" + "ab".repeat(length));
      const size = ethers.dataLength(block);
      const spec = exactSpec(Keys.Bytes, length);
      const args = [block, size, 0, spec, 0, 8, true];
      const [whole, base] = await take.inspect(...args);
      const [payload] = await unpack.inspect(...args);
      expect(whole).eq(base | ((base + BigInt(size)) << 32n));
      expect(whole >> 64n).eq(0n);
      expect(payload).eq(whole + 8n);
      for (const amount of [0, Math.floor(length / 2), length]) {
        const [abs, rest, sourceBase] = await take.enterExact(block, size, spec, amount);
        expect(abs).eq(sourceBase + 8n);
        expect(rest).eq((abs + BigInt(amount)) | ((sourceBase + BigInt(size)) << 32n));
        expect(rest >> 64n).eq(0n);
      }
      const tooMuch = await outcome(() => take.enterExact(block, size, spec, length + 1));
      expect(tooMuch.error).eq(INVALID);
      expect((await outcome(() => take.enterExact(block, size, spec, ethers.MaxUint256))).error).eq(INVALID);
      for (const [input, bound, badSpec] of [
        [block, size - 1, spec],
        [concat(block, block), size * 2, spec],
        [block, size, exactSpec(Keys.String, length)],
        [block, size, rangedSpec(Keys.Bytes, length + 1, 0, 0)],
      ]) {
        const invalidArgs = [input, bound, 0, badSpec, 0, 8, true];
        const result = await outcome(() => take.inspect(...invalidArgs));
        expect(result.error).eq(INVALID);
        expect(result).deep.eq(await outcome(() => unpack.inspect(...invalidArgs)));
        expect((await outcome(() => take.enterExact(input, bound, badSpec, 0))).error).eq(INVALID);
      }
    }
    expect((await outcome(() => take.raw(2n | (1n << 32n), exactSpec(Keys.Bytes, 0), 0, 8))).error).eq(INVALID);
  });
});
