import { expect } from "chai";
import { ethers } from "ethers";
import { deploy } from "./helpers/setup.js";
import { concat, encodeBlock, exactSpec, rangedSpec, Keys } from "./helpers/blocks.js";
import { size } from "./helpers/cursor-consumers.js";

describe("CursorBlocks generic unpack", () => {
  let helper: any;
  before(async () => { helper = await deploy("TestCursorGenericUnpack"); });
  for (const keyed of [true, false]) describe(keyed ? "key" : "spec", () => {
    it("enters a validated prefix with its original absolute start and remaining payload", async () => {
      const block = encodeBlock(Keys.Bytes, "0x" + "ab".repeat(96));
      const source = concat("0x123456", block, block);
      for (const amount of [0, 1, 32, 64, 96]) {
        const [abs, payload, original, next] = await helper.prefix(source, 3, size(source), exactSpec(Keys.Bytes, 96), amount, keyed);
        expect(abs).eq((original & 0xffffffffn) + 8n);
        expect(payload).eq((abs + BigInt(amount)) | ((abs + 96n) << 32n));
        expect(next).eq(original + 104n);
      }
      for (const [length, amount, reason] of [[size(source), 97, "InvalidBlock"], [106, 64, "OutOfBounds"]] as const) {
        let error: unknown;
        try { await helper.prefix(source, 3, length, exactSpec(Keys.Bytes, 96), amount, keyed); }
        catch (e: any) { error = e.data ?? e.info?.error?.data; }
        expect(error).eq(ethers.id(reason + "()").slice(0, 10));
      }
    });

    it("returns a clean payload and preserves the enclosing end and metadata", async () => {
      for (const key of [Keys.Bytes, Keys.List, "0xdeadbeef"]) for (const length of [0, 1, 33, 160]) {
        const block = encodeBlock(key, "0x" + "ab".repeat(length));
        const source = concat("0x123456", block, block);
        for (const metadata of [0n, ethers.MaxUint256]) {
          const [payload, next, original] = await helper.inspect(source, 3, size(source), metadata, exactSpec(key, length), keyed);
          const abs = original & 0xffffffffn;
          expect(payload).eq((abs + 8n) | ((abs + BigInt(8 + length)) << 32n));
          expect(next).eq(original + BigInt(8 + length));
        }
      }
    });
    it("chains variable-length blocks through returned cursors", async () => {
      const source = concat(...[0, 1, 33, 64].map(n => encodeBlock(Keys.Bytes, "0x" + "ab".repeat(n))));
      const r = await helper.scan(source, rangedSpec(Keys.Bytes, 0, 0, 0), keyed);
      expect(r[0]).eq(4n); expect(r[1]).eq(98n);
    });
    it("checks schema before bounds and rejects truncated or reversed logical ranges", async () => {
      const block = encodeBlock(Keys.Bytes, "0x" + "ab".repeat(32));
      const source = concat("0xff", block, block);
      const good = exactSpec(Keys.Bytes, 32);
      const cases: [number, number, bigint, string][] = [
        ...[0, 1, 7, 8, 39].map(n => [1, 1 + n, good, "OutOfBounds"] as [number, number, bigint, string]),
        [1, 0, good, "OutOfBounds"], [1, 2, exactSpec(Keys.List, 32), "InvalidBlock"],
      ];
      if (!keyed) cases.push([1, 2, exactSpec(Keys.Bytes, 31), "InvalidBlock"],
        [1, 41, rangedSpec(Keys.Bytes, 33, 64, 0), "InvalidBlock"],
        [1, 41, rangedSpec(Keys.Bytes, 0, 31, 0), "InvalidBlock"]);
      for (const [offset, length, spec, reason] of cases) {
        let error: unknown;
        try { await helper.inspect(source, offset, length, 0, spec, keyed); }
        catch (e: any) { error = e.data ?? e.info?.error?.data; }
        expect(error).eq(ethers.id(reason + "()").slice(0, 10));
      }
      // Inclusive range endpoints are accepted by the spec overload.
      for (const spec of [rangedSpec(Keys.Bytes, 32, 64, 0), rangedSpec(Keys.Bytes, 0, 32, 0)]) {
        await helper.inspect(source, 1, 41, 0, spec, keyed);
      }
    });
  });
});
