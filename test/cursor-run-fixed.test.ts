import { expect } from "chai";
import { ethers } from "ethers";
import { deploy } from "./helpers/setup.js";
import { concat, encodeBlock, Keys } from "./helpers/blocks.js";
import { balance, size } from "./helpers/cursor-consumers.js";

describe("CursorBlocks.expectRunFixed", () => {
  let helper: any;
  const header = (BigInt(Keys.Balance) << 32n) | 64n;
  before(async () => { helper = await deploy("TestCursorRunFixed"); });
  it("validates complete streams without advancing or changing metadata", async () => {
    for (const count of [0, 1, 4, 32]) for (const metadata of [0n, ethers.MaxUint256]) {
      const source = concat("0x123456", ...Array(count).fill(balance), balance);
      const cur = await helper.validate(source, 3, 3 + count * 72, metadata, header);
      expect((cur >> 32n & 0xffffffffn) - (cur & 0xffffffffn)).eq(BigInt(count * 72));
      expect(cur >> 64n).eq(metadata >> 64n);
    }
  });
  it("supports other fixed sizes including zero payloads", async () => {
    for (const length of [0, 1, 32, 160]) {
      const block = encodeBlock(Keys.Bytes, "0x" + "ab".repeat(length));
      const source = concat(block, block);
      await helper.validate(source, 0, size(source), 0, (BigInt(Keys.Bytes) << 32n) | BigInt(length));
    }
  });
  async function rejects(source: string, offset: number, length: number, reason: string, expected = header) {
    let error: unknown;
    try { await helper.validate(source, offset, length, 0, expected); }
    catch (e: any) { error = e.data ?? e.info?.error?.data; }
    expect(error).eq(ethers.id(reason + "()").slice(0, 10));
  }
  it("rejects reversed ranges and truncated logical streams despite trailing calldata", async () => {
    const source = concat(balance, balance);
    await rejects(source, 2, 1, "OutOfBounds");
    for (const length of [1, 7, 8, 71, 73, 143]) await rejects(source, 0, length, "OutOfBounds");
  });
  it("validates every header and preserves per-block bounds-before-header ordering", async () => {
    const wrongKey = encodeBlock(Keys.Bytes, "0x" + "00".repeat(64));
    const wrongLength = encodeBlock(Keys.Balance, "0x" + "00".repeat(65));
    await rejects(concat(balance, wrongKey), 0, 144, "InvalidBlock");
    await rejects(wrongLength, 0, 72, "InvalidBlock");
    await rejects(wrongKey, 0, 71, "OutOfBounds");
    await rejects(concat(wrongKey, "0xff"), 0, 73, "InvalidBlock");
    await rejects(balance, 0, 72, "InvalidBlock", header | (1n << 64n));
  });
});
