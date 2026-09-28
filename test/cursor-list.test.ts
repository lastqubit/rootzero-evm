import { expect } from "chai";
import { ethers } from "ethers";
import { deploy } from "./helpers/setup.js";
import { concat, encodeBlock, Keys } from "./helpers/blocks.js";
import { size } from "./helpers/cursor-consumers.js";

for (const kind of ["List", "Bytes", "String"] as const) describe(`CursorBlocks.unpack${kind}`, () => {
  const key = Keys[kind];
  let helper: any;
  before(async () => { helper = await deploy(`TestCursor${kind}`); });
  it("returns a clean items range and preserves source end and metadata", async () => {
    for (const length of [0, 1, 31, 32, 33, 256]) for (const metadata of [0n, ethers.MaxUint256]) {
      // Deliberately not a valid item stream: unpackList validates only the container.
      const block = encodeBlock(key, "0x" + "ab".repeat(length));
      const source = concat("0x123456", block, block);
      const [items, next, original] = await helper.inspect(source, 3, size(source), metadata);
      const abs = original & 0xffffffffn;
      expect(items).eq((abs + 8n) | ((abs + BigInt(8 + length)) << 32n));
      expect(next).eq(original + BigInt(8 + length));
    }
  });
  it("chains returned source cursors through consecutive lists", async () => {
    const source = concat(...[0, 33, 1, 64].map(n => encodeBlock(key, "0x" + "ff".repeat(n))));
    const r = await helper.scan(source);
    expect(r[0]).eq(4n); expect(r[1]).eq(98n);
  });
  it("checks key before containment and rejects logical truncation and reversed ranges", async () => {
    const block = encodeBlock(key, "0x" + "ab".repeat(32));
    const wrong = encodeBlock(key === Keys.Bytes ? Keys.List : Keys.Bytes, "0x" + "ab".repeat(32));
    for (const [source, offset, length, reason] of [
      ...[0, 1, 7, 8, 39].map(n => [block, 0, n, "OutOfBounds"] as const),
      [block, 1, 0, "InvalidBlock"], [wrong, 0, 1, "InvalidBlock"],
      [block, 0, 0, "OutOfBounds"], ["0xff" + block.slice(2), 1, 0, "OutOfBounds"],
    ] as const) {
      let error: unknown;
      try { await helper.inspect(source, offset, length, 0); }
      catch (e: any) { error = e.data ?? e.info?.error?.data; }
      expect(error).eq(ethers.id(reason + "()").slice(0, 10));
    }
  });
});
