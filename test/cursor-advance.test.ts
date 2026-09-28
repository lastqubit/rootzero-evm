import { expect } from "chai";
import { ethers } from "ethers";
import { deploy } from "./helpers/setup.js";

describe("CursorBlocks.advance", () => {
  it("validates only the header at an absolute position", async () => {
    const helper = await deploy("TestCursorAdvance");
    const header = "0x1234567800000040";
    await helper.expectHeader("0xff" + header.slice(2), 1, BigInt(header));
    // A matching header succeeds without its declared payload: containment is separate.
    await helper.expectHeader(header, 0, BigInt(header));
    for (const expected of [0x1234567900000040n, 0x1234567800000041n, (1n << 64n) | BigInt(header)]) {
      let error: unknown;
      try { await helper.expectHeader(header, 0, expected); }
      catch (e: any) { error = e.data ?? e.info?.error?.data; }
      expect(error).eq(ethers.id("InvalidBlock()").slice(0, 10));
    }
  });

  it("advances exact byte counts while preserving boundaries and metadata", async () => {
    const helper = await deploy("TestCursorAdvance"), max = (1n << 32n) - 1n;
    for (const metadata of [0n, ethers.MaxUint256 & ~((1n << 64n) - 1n)]) {
      for (const [pos, end, size] of [[0n, 0n, 0n], [5n, 69n, 0n], [5n, 69n, 32n],
        [5n, 69n, 64n], [max - 8n, max, 8n], [0n, max, max]]) {
        const cur = pos | (end << 32n) | metadata;
        expect(await helper.advance(cur, size)).eq(cur + size);
      }
      // All sizes satisfy the primitive's documented size <= uint32.max + 8 precondition.
      for (const [pos, end, size] of [[6n, 5n, 0n], [5n, 69n, 65n], [max, max, 1n],
        [0n, max, max + 8n], [max, max, max + 8n]]) {
        let error: unknown;
        try { await helper.advance(pos | (end << 32n) | metadata, size); }
        catch (e: any) { error = e.data ?? e.info?.error?.data; }
        expect(error).eq(ethers.id("OutOfBounds()").slice(0, 10));
      }
    }
  });
});
