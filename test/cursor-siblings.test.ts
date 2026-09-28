import { expect } from "chai";
import { ethers } from "ethers";
import { deploy } from "./helpers/setup.js";
import { concat, encodeBlock, Keys } from "./helpers/blocks.js";
const invalid = ethers.id("InvalidBlock()").slice(0, 10), bounds = ethers.id("OutOfBounds()").slice(0, 10);
const size = (s: string) => ethers.getBytes(s).length;
async function errorOf(call: Promise<any>) {
  try {
    await call;
    return undefined;
  }
  catch (e: any) {
    const data = e.data ?? e.info?.error?.data;
    if (typeof data !== "string")
      throw e;
    return data;
  }
}
describe("Cursor sibling unpacking", function () {
  this.timeout(120000);
  for (const kind of ["Relay", "Context"] as const)
    for (const variant of ["Baseline", "Composed", "Checked", "Fused", "RangeReference"])
      describe(`${kind}/${variant}`, () => {
        let h: any;
        const prefix = kind === "Context" ? ethers.toBeHex(ethers.MaxUint256, 32) : "0x";
        const block = (a: string, b: string) => encodeBlock(Keys[kind], concat(prefix, encodeBlock(Keys.Bytes, a), encodeBlock(Keys.Bytes, b)));
        before(async () => { h = await deploy(`Cursor${kind}${variant}`); });
        it("returns separate exact payload cursors for empty, unaligned, and unequal siblings", async () => {
          for (const [x, y] of [[0, 0], [0, 33], [33, 0], [1, 31], [31, 1], [32, 33], [256, 129]]) {
            const a = "0x" + "ab".repeat(x), b = "0x" + "cd".repeat(y), value = block(a, b);
            const source = concat("0x123456", value, block("0xff", "0xee"));
            const r = await h.inspect(source, size(source), 3), first = r[3] + BigInt(3 + 8 + size(prefix) + 8), next = first + BigInt(x);
            expect(r[0]).eq(kind === "Context" ? ethers.toBeHex(ethers.MaxUint256, 32) : ethers.ZeroHash);
            expect(r[1]).eq(first | (next << 32n));
            expect(r[2]).eq((next + 8n) | ((next + 8n + BigInt(y)) << 32n));
            expect(r[1] >> 64n).eq(0n);
            expect(r[2] >> 64n).eq(0n);
            expect(r[4]).eq(a);
            expect(r[5]).eq(b);
          }
        });
        it("rejects parent truncation and reversed ranges despite valid trailing calldata", async () => {
          const value = block("0xabcdef", "0x1234567890");
          for (const length of [0, 7, 8, size(value) - 9, size(value) - 1]) {
            expect(await errorOf(h.inspect(value, length, 0))).eq(bounds);
            expect(await errorOf(h.values(value, length, 0))).eq(bounds);
          }
          const source = concat("0x123456", value);
          expect(await errorOf(h.inspect(source, 2, 3))).eq(bounds);
        });
        it("rejects missing headers, malformed siblings, and extra children even when cursors are discarded", async () => {
          const child = encodeBlock(Keys.Bytes, "0x");
          const bodies = [
            concat(prefix, encodeBlock(Keys.String, "0x"), child),
            concat(prefix, child, encodeBlock(Keys.String, "0x")),
            concat(prefix, child), concat(prefix, child, Keys.Bytes, "0x000000"),
            concat(prefix, child, child, "0xff"), concat(prefix, child, child, child),
            concat(prefix, child, Keys.Bytes, "0xffffffff"),
          ];
          for (const body of bodies) {
            const value = encodeBlock(Keys[kind], body);
            expect(await errorOf(h.inspect(value, size(value), 0))).eq(invalid);
            expect(await errorOf(h.values(value, size(value), 0))).eq(invalid);
          }
          if (kind === "Context")
            for (const length of [0, 1, 31]) {
              const source = concat(Keys.Context, ethers.toBeHex(length, 4), prefix, child, child);
              expect(await errorOf(h.inspect(source, size(source), 0))).eq(invalid);
            }
        });
        it("rejects a first child extending past its parent without narrowing its end", async () => {
          for (const length of [9, 256, 0xffffffff]) {
            const value = encodeBlock(Keys[kind], concat(prefix, Keys.Bytes, ethers.toBeHex(length, 4), encodeBlock(Keys.Bytes, "0x")));
            const expected = variant === "Composed" ? bounds : invalid;
            expect(await errorOf(h.inspect(value, size(value), 0))).eq(expected);
            expect(await errorOf(h.values(value, size(value), 0))).eq(expected);
          }
        });
        if (variant !== "Baseline")
          it("checks the parent before malformed child data", async () => {
            const value = concat(Keys[kind], "0xffffffff", prefix, encodeBlock(Keys.String, "0x"));
            expect(await errorOf(h.inspect(value, size(value), 0))).eq(bounds);
            const wrong = concat(Keys.Step, "0xffffffff");
            expect(await errorOf(h.inspect(wrong, 0, 0))).eq(invalid);
          });
      });
});
