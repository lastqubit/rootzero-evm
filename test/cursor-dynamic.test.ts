import { expect } from "chai";
import { ethers } from "ethers";
import { deploy } from "./helpers/setup.js";
import { concat, encodeBlock, Keys } from "./helpers/blocks.js";

const invalid = ethers.id("InvalidBlock()").slice(0, 10);
const bounds = ethers.id("OutOfBounds()").slice(0, 10);
const words = concat(ethers.toBeHex(ethers.MaxUint256, 32), ethers.toBeHex(7, 32));
const size = (s: string) => ethers.getBytes(s).length;
const step = (data: string) => encodeBlock(Keys.Step, concat(words, encodeBlock(Keys.Input, data)));
async function errorOf(call: Promise<any>) {
  try { await call; return undefined; }
  catch (e: any) { const data = e.data ?? e.info?.error?.data; if (typeof data !== "string") throw e; return data; }
}

describe("Cursor dynamic STEP unpacking", function () {
  this.timeout(120_000);
  for (const variant of ["Baseline", "Composed", "Expected", "Fused", "RangeReference"]) describe(variant, () => {
    let helper: any;
    before(async () => { helper = await deploy(`CursorDynamic${variant}`); });
    it("decodes fixed words and exact child payloads, including empty and unaligned ranges", async () => {
      for (const length of [0, 1, 31, 32, 33, 128, 1024]) {
        const data = "0x" + "ab".repeat(length);
        const block = step(data);
        const source = concat("0x123456", block, step("0xbeef"));
        const r = await helper.inspect(source, size(source), 3);
        expect(r[0]).eq(ethers.MaxUint256); expect(r[1]).eq(7n);
        expect(r[2]).eq((r[3] + 83n) | ((r[3] + BigInt(3 + size(block))) << 32n));
        expect(r[2] >> 64n).eq(0n); expect(r[4]).eq(data);
      }
    });
    it("rejects logical truncation even when the full block exists later in calldata", async () => {
      const block = step("0xabcdef");
      for (const length of [0, 7, 8, 39, 71, 72, 79, 80, 82]) {
        expect(await errorOf(helper.inspect(block, length, 0))).eq(bounds);
        expect(await errorOf(helper.values(block, length, 0))).eq(bounds);
      }
      const source = concat("0x123456", block);
      expect(await errorOf(helper.inspect(source, 2, 3))).eq(bounds);
    });
    it("rejects short fixed prefixes and partial child headers despite valid trailing calldata", async () => {
      for (const length of [0, 1, 31, 32, 63, 64, 65, 71]) {
        const source = concat(Keys.Step, ethers.toBeHex(length, 4), words, encodeBlock(Keys.Input, "0x"));
        expect(await errorOf(helper.inspect(source, size(source), 0))).eq(invalid);
        expect(await errorOf(helper.values(source, size(source), 0))).eq(invalid);
      }
    });
    it("rejects wrong keys, child length mismatch, and extra children inside the parent", async () => {
      const cases = [
        encodeBlock(Keys.Call, concat(words, encodeBlock(Keys.Input, "0x"))),
        encodeBlock(Keys.Step, concat(words, encodeBlock(Keys.String, "0x"))),
        encodeBlock(Keys.Step, concat(words, Keys.Input, "0x00000002", "0xab")),
        encodeBlock(Keys.Step, concat(words, Keys.Input, "0x00000000", "0xab")),
        encodeBlock(Keys.Step, concat(words, Keys.Input, "0xffffffff")),
        encodeBlock(Keys.Step, concat(words, encodeBlock(Keys.Input, "0x"), encodeBlock(Keys.Input, "0x"))),
      ];
      for (const source of cases) {
        expect(await errorOf(helper.inspect(source, size(source), 0))).eq(invalid);
        expect(await errorOf(helper.values(source, size(source), 0))).eq(invalid);
      }
    });
    if (variant !== "Baseline") it("checks the parent bound before inspecting the dynamic child", async () => {
      const source = concat(Keys.Step, "0xffffffff", words, encodeBlock(Keys.String, "0x"));
      expect(await errorOf(helper.inspect(source, size(source), 0))).eq(bounds);
      const wrong = concat(Keys.Call, "0xffffffff");
      expect(await errorOf(helper.inspect(wrong, 0, 0))).eq(invalid);
    });
  });
});
