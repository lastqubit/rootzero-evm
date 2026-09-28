import { expect } from "chai";
import { ethers } from "ethers";
import { deploy } from "./helpers/setup.js";
import { concat, encodeBlock, exactSpec, Keys } from "./helpers/blocks.js";
import { size } from "./helpers/cursor-consumers.js";

describe("Advancing CursorBlocks selectors", () => {
  let helper: any;
  before(async () => { helper = await deploy("TestCursorSelectionNext"); });
  for (const mode of [0, 1, 2, 3]) it(`selection ${mode} returns header-inclusive range and preserved source lanes`, async () => {
    for (const length of [0, 1, 32, 65]) for (const metadata of [0n, ethers.MaxUint256]) {
      const block = encodeBlock(Keys.Bytes, "0x" + "ab".repeat(length));
      const source = concat("0x123456", block, block);
      const [selected, next, original] = await helper.inspect(source, 3, size(source), metadata, exactSpec(Keys.Bytes, length), mode);
      const abs = original & 0xffffffffn;
      expect(selected).eq(abs | ((abs + BigInt(8 + length)) << 32n));
      expect(next).eq(original + BigInt(8 + length));
    }
  });
  it("chains every selector and both prefix overloads using only returned source cursors", async () => {
    for (const length of [0, 1, 32, 65]) {
      const block = encodeBlock(Keys.Bytes, "0x" + "ab".repeat(length));
      const source = concat(block, block, block);
      for (const mode of [0, 1, 2, 3, 4, 5, 6, 7]) for (const amount of [0, length]) {
        const r = await helper.scan(source, exactSpec(Keys.Bytes, length), mode, amount);
        expect(r[0]).eq(3n);
        expect(r[1]).eq(BigInt(3 * (mode < 4 ? length + 8 : mode === 6 ? length : length - amount)));
      }
    }
  });
  it("fixed payload helpers return clean ranges and preserve source lanes", async () => {
    for (const length of [0, 1, 32, 65]) {
      const block = encodeBlock(Keys.Bytes, "0x" + "ab".repeat(length));
      const source = concat("0x123456", block, block);
      for (const prefix of [false, true]) for (const amount of [0, length]) for (const metadata of [0n, ethers.MaxUint256]) {
        const [abs, payload, next, original] = await helper.fixedPayload(source, 3, size(source), metadata, exactSpec(Keys.Bytes, length) >> 192n, amount, prefix);
        const body = (original & 0xffffffffn) + 8n;
        if (prefix) expect(abs).eq(body);
        expect(payload).eq((body + BigInt(prefix ? amount : 0)) | ((body + BigInt(length)) << 32n));
        expect(next).eq(original + BigInt(length + 8));
      }
    }
  });
  it("fixed payload helpers preserve header, bounds, and prefix error precedence", async () => {
    const block = encodeBlock(Keys.Bytes, "0x" + "ab".repeat(32));
    const source = concat("0xff", block, block), header = exactSpec(Keys.Bytes, 32) >> 192n;
    for (const prefix of [false, true]) {
      const cases: [bigint, number, number, string][] = [
        [header, 0, 0, "OutOfBounds"], [header, 40, 33, "OutOfBounds"],
        [header + 1n, 2, 33, "InvalidBlock"],
        [header ^ (1n << 32n), 41, 0, "InvalidBlock"],
        [header | (1n << 64n), 41, 0, "InvalidBlock"],
      ];
      if (prefix) cases.push([header, 41, 33, "InvalidBlock"]);
      for (const [expected, length, amount, reason] of cases) {
        let error: unknown;
        try { await helper.fixedPayload(source, 1, length, 0, expected, amount, prefix); }
        catch (e: any) { error = e.data ?? e.info?.error?.data; }
        expect(error).eq(ethers.id(reason + "()").slice(0, 10));
      }
    }
  });
});
