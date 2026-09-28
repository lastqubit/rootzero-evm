import { expect } from "chai";
import { ethers } from "ethers";
import { deploy } from "./helpers/setup.js";
import { encodeBlock, Keys } from "./helpers/blocks.js";
import "./helpers/matchers.js";

describe("CursorBlocks conversions", () => {
  let helper: any;
  before(async () => { helper = await deploy("TestCursorConversions"); });
  it("checks calldata bounds while preserving zero, empty, and metadata-bearing cursors", async () => {
    // checked(uint) has exactly 36 bytes of calldata.
    for (const [start, end] of [[0, 0], [0, 36], [1, 35], [36, 36]]) {
      for (const metadata of [0n, ethers.MaxUint256 & ~((1n << 64n) - 1n)]) {
        const cur = BigInt(start) | (BigInt(end) << 32n) | metadata;
        const input = helper.interface.encodeFunctionData("checked", [cur]);
        const r = await helper.checked(cur);
        expect(r[0]).eq(ethers.dataSlice(input, start, end));
        expect(r[1]).eq(BigInt(start));
        expect(r[2]).eq(0n);
        expect(r[3]).eq(cur);
      }
    }
    for (const [start, end] of [[1, 0], [36, 35], [0, 37], [37, 37], [0, 0xffffffff]]) {
      const cur = BigInt(start) | (BigInt(end) << 32n);
      await expect(helper.checked(cur)).revertedWithCustomError(helper, "OutOfBounds");
    }
  });
  it("views the remaining range without allocation, advancement, or interpreting metadata", async () => {
    const source = "0x00112233445566778899aabbccddeeff";
    for (const [start, end, skip] of [[0, 15, 0], [1, 14, 3], [3, 7, 4], [15, 15, 0]]) {
      for (const metadata of [0n, ethers.MaxUint256]) {
        const [data, textBytes, offset, allocated, before, after] = await helper.inspect(source, start, end, skip, metadata);
        expect(data).eq(ethers.dataSlice(source, start + skip, end));
        expect(textBytes).eq(data); // Includes arbitrary bytes; no UTF-8 validation.
        expect(offset).eq(BigInt(start + skip));
        expect(allocated).eq(0n);
        expect(after).eq(before);
        expect(after >> 64n).eq(metadata >> 64n);
      }
    }
    const r = await helper.inspect("0x", 0, 0, 0, ethers.MaxUint256);
    expect(r[0]).eq("0x"); expect(r[1]).eq("0x"); expect(r[3]).eq(0n);
  });
  it("converts a validated STRING payload to calldata or memory when requested", async () => {
    for (const text of ["", "hello", "a\0b", "Gr??e ??"]) {
      const block = encodeBlock(Keys.String, ethers.hexlify(ethers.toUtf8Bytes(text)));
      expect(Array.from(await helper.unpackText(block))).deep.eq([text, text]);
    }
  });
});
