import { expect } from "chai";
import { ethers } from "ethers";
import { deploy } from "./helpers/setup.js";
import { encodeBlock, Keys } from "./helpers/blocks.js";
import "./helpers/matchers.js";

describe("Whole-stream selection", () => {
  let helper: any;
  before(async () => { helper = await deploy("TestExecutionStreams"); });
  const header = (BigInt(Keys.Bytes) << 32n) | 3n;
  it("validates every generic or fixed block and consumes metadata-free cursors", async () => {
    for (const fixed of [false, true]) for (const state of [false, true]) for (const declared of [false, true]) {
      for (const data of ["0x", ethers.concat([encodeBlock(Keys.Bytes, "0x010203"), encodeBlock(Keys.Bytes, fixed ? "0x040506" : "0x")])]) {
        const r = await helper.select(data, Keys.Bytes, header, fixed, state, declared);
        expect(r.selected).eq(data);
        expect(r.beforeCur >> 64n).eq(0n);
        expect(r.afterCur >> 64n).eq(0n);
        expect(r.selectedCur >> 64n).eq(0n);
        expect(r.selectedCur).eq(r.beforeCur & ((1n << 64n) - 1n));
        expect(r.afterCur >> 32n).eq(r.beforeCur >> 32n);
        expect(r.afterCur & 0xffffffffn).eq((r.beforeCur >> 32n) & 0xffffffffn);
        expect(r.otherCur).eq(0n);
      }
    }
  });
  it("validates streams even when the descriptor declares EMPTY", async () => {
    for (const fixed of [false, true]) for (const state of [false, true]) {
      await expect(helper.select("0x1234", Keys.Bytes, header, fixed, state, false)).revertedWithCustomError(helper, "OutOfBounds");
    }
  });
  it("rejects wrong later headers, partial headers, truncated payloads, and reversed ranges", async () => {
    const good = encodeBlock(Keys.Bytes, "0x010203");
    for (const fixed of [false, true]) {
      const badKey = ethers.concat([good, encodeBlock(Keys.String, "0x040506")]);
      await expect(helper.validate(badKey, 0, ethers.dataLength(badKey), Keys.Bytes, header, fixed)).revertedWithCustomError(helper, "InvalidBlock");
      for (const state of [false, true]) {
        await expect(helper.select(badKey, Keys.Bytes, header, fixed, state, true)).revertedWithCustomError(helper, "InvalidBlock");
      }
      for (const data of [ethers.concat([good, "0x01"]), ethers.dataSlice(good, 0, 10)]) {
        await expect(helper.validate(data, 0, ethers.dataLength(data), Keys.Bytes, header, fixed)).revertedWithCustomError(helper, "OutOfBounds");
      }
      await expect(helper.validate(good, 2, 1, Keys.Bytes, header, fixed)).revertedWithCustomError(helper, "OutOfBounds");
    }
    const wrongLength = encodeBlock(Keys.Bytes, "0x01020304");
    await expect(helper.validate(wrongLength, 0, 12, Keys.Bytes, header, true)).revertedWithCustomError(helper, "InvalidBlock");
    await helper.validate(wrongLength, 0, 12, Keys.Bytes, header, false);
  });
});
