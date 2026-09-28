import { expect } from "chai";
import { ethers } from "ethers";
import { deploy } from "./helpers/setup.js";
import { concat, encodeBlock, Keys } from "./helpers/blocks.js";

const size = (data: string) => ethers.getBytes(data).length;
const word = (value: bigint | number) => ethers.toBeHex(value, 32);
const invalid = ethers.id("InvalidBlock()").slice(0, 10);
const bounds = ethers.id("OutOfBounds()").slice(0, 10);
async function errorOf(call: Promise<any>) {
  try { await call; return undefined; }
  catch (e: any) { const data = e.data ?? e.info?.error?.data; if (typeof data !== "string") throw e; return data; }
}

describe("Uniform CursorBlocks unpacking contract", function () {
  this.timeout(120_000);
  for (const kind of ["64", "160", "Balance", "Step", "Relay", "Context"]) describe(kind, () => {
    let helper: any;
    const fixed = ["64", "160", "Balance"].includes(kind);
    const key = kind === "64" || kind === "160" ? "0xdeadbeef" : Keys[kind as keyof typeof Keys];
    const values = kind === "160" ? [1n, 2n, 3n, 4n, ethers.MaxUint256]
      : kind === "Relay" ? [] : kind === "Context" ? [ethers.MaxUint256] : [ethers.MaxUint256, 7n];
    const prefix = concat(...values.map(word));
    const make = (length: number) => {
      const children = fixed ? [] : kind === "Step" ? ["0x" + "ab".repeat(length)] : ["0x" + "ab".repeat(length), "0x123456"];
      const block = encodeBlock(key, concat(prefix, ...children.map(c => encodeBlock(Keys.Bytes, c))));
      return { children, block };
    };
    before(async () => { helper = await deploy(`CursorUniform${kind}`); });
    it("returns values, clean child ranges, then nextCur with source end and metadata preserved", async () => {
      for (const length of fixed ? [0] : [0, 1, 31, 32, 33, 256]) {
        const { children, block } = make(length);
        const source = concat("0x123456", block, block);
        for (const metadata of [0n, 0xa5n << 64n, ethers.MaxUint256]) for (const limit of [3 + size(block), size(source)]) {
          const r = await helper.inspect(source, limit, 3, metadata, key);
          expect(Array.from(r[0])).deep.eq(values.map(word));
          expect(r[2] & 0xffffffffn).eq(r[4] + BigInt(3 + size(block)));
          expect(r[2] >> 32n).eq(r[3] >> 32n);
          expect(r[2] >> 64n).eq(metadata >> 64n);
          let childAbs = r[4] + BigInt(3 + 8 + size(prefix));
          expect(r[1].length).eq(children.length);
          for (let i = 0; i < children.length; i++) {
            const bodyAbs = childAbs + 8n, endAbs = bodyAbs + BigInt(size(children[i]));
            expect(r[1][i]).eq(bodyAbs | (endAbs << 32n));
            expect(r[1][i] >> 64n).eq(0n);
            childAbs = endAbs;
          }
        }
      }
    });
    it("rejects logical truncation and reversed ranges even with valid trailing calldata", async () => {
      const { block } = make(33), source = concat("0x123456", block, block);
      for (const limit of [0, 2, 3, 10, 3 + size(block) - 1]) {
        expect(await errorOf(helper.inspect(source, limit, 3, ethers.MaxUint256, key))).eq(bounds);
      }
      expect(await errorOf(helper.onlyValues(ethers.dataSlice(block, 0, size(block) - 1), key))).eq(bounds);
    });
    it("validates the complete shape when cursor returns are discarded", async () => {
      const cases = fixed ? [encodeBlock(key, "0x"), encodeBlock(key, concat(prefix, "0xff"))]
        : [encodeBlock(key, prefix), encodeBlock(key, concat(prefix, encodeBlock(Keys.String, "0x"))),
          encodeBlock(key, concat(prefix, Keys.Bytes, "0xffffffff")),
          encodeBlock(key, concat(prefix, encodeBlock(Keys.Bytes, "0x"), encodeBlock(Keys.Bytes, "0x"), "0xff"))];
      for (const source of cases) {
        expect(await errorOf(helper.inspect(source, size(source), 0, 0, key))).eq(invalid);
        expect(await errorOf(helper.onlyValues(source, key))).eq(invalid);
      }
      const wrong = encodeBlock("0x01020304", prefix);
      expect(await errorOf(helper.inspect(wrong, 0, 0, 0, key))).eq(invalid);
    });
    it("consumes a complete stream using only the returned cursor", async () => {
      const blocks = [0, 1, 33].map(length => make(length));
      const r = await helper.measure(concat(...blocks.map(b => b.block)), key);
      const expected = blocks.reduce((sum, b) => sum + values.reduce((a, v) => a + v, 0n) + BigInt(b.children.reduce((a, c) => a + size(c), 0)), 0n) & ethers.MaxUint256;
      expect(r[1]).eq(expected);
      expect(r[2] >> 64n).eq(0xa5n);
      expect(r[2] & 0xffffffffn).eq((r[2] >> 32n) & 0xffffffffn);
    });
  });
});
