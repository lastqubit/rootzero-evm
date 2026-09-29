import { expect } from "chai";
import { ethers } from "ethers";
import { deploy } from "./helpers/setup.js";
import { concat, encodeBlock, exactSpec, Keys } from "./helpers/blocks.js";
import "./helpers/matchers.js";

describe("Fixed-header exact selection", () => {
  it("returns clean complete or payload ranges, including empty and unaligned payloads", async () => {
    const helper = await deploy("TestCursorFixedExact");
    for (const size of [0, 1, 31, 32, 65]) {
      const block = encodeBlock(Keys.Bytes, "0x" + "ab".repeat(size));
      const source = concat("0x123456", block, "0xffffff");
      for (const payload of [false, true]) for (const metadata of [0n, ethers.MaxUint256]) {
        const [selected, original] = await helper.inspect(source, 3, 11 + size,
          exactSpec(Keys.Bytes, size) >> 192n, metadata, payload);
        const start = (original & 0xffffffffn) + (payload ? 8n : 0n);
        expect(selected).eq(start | (original & (0xffffffffn << 32n)));
        expect(selected >> 64n).eq(0n);
        expect(original >> 64n).eq(metadata >> 64n);
      }
    }
  });

  it("rejects mismatched headers, upper header bits, non-exact ranges, and full-width end overflow", async () => {
    const helper = await deploy("TestCursorFixedExact");
    const block = encodeBlock(Keys.Bytes, "0x" + "ab".repeat(32));
    const source = concat("0xff", block, block);
    const header = exactSpec(Keys.Bytes, 32) >> 192n;
    for (const payload of [false, true]) {
      for (const end of [0, 1, 8, 9, 40, 42, 81]) {
        await expect(helper.inspect(source, 1, end, header, ethers.MaxUint256, payload))
          .revertedWithCustomError(helper, "InvalidBlock");
      }
      for (const wrong of [header + 1n, header ^ (1n << 32n), header | (1n << 64n)]) {
        await expect(helper.inspect(source, 1, 41, wrong, 0, payload))
          .revertedWithCustomError(helper, "InvalidBlock");
      }
      const huge = concat(Keys.Bytes, "0xffffffff");
      await expect(helper.inspect(huge, 0, 8, (BigInt(Keys.Bytes) << 32n) | 0xffffffffn, 0, payload))
        .revertedWithCustomError(helper, "InvalidBlock");
      // An out-of-calldata zero header must not let position + 8 wrap into the end lane.
      await expect(helper.select(0xffffffffn | (7n << 32n), 0, payload))
        .revertedWithCustomError(helper, "InvalidBlock");
    }
  });
});
