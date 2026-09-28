import { expect } from "chai";
import { ethers } from "ethers";
import { deploy } from "./helpers/setup.js";

describe("CursorBlocks raw absolute readers", () => {
  const widths = [1, 2, 4, 8, 16, 32];

  it("returns leading bytes at unaligned positions and zero-pads beyond calldata", async () => {
    const helper = await deploy("CursorRawReadersCurrent");
    for (const length of [0, 1, 2, 3, 7, 15, 31, 32, 33, 65]) {
      const source = Uint8Array.from({ length }, (_, i) => (i * 37 + 11) % 256);
      for (const offset of new Set([0, 1, 3, Math.max(0, length - 1), length, length + 7])) {
        const expected = widths.map(width => {
          const value = new Uint8Array(width);
          value.set(source.slice(offset, offset + width));
          return ethers.hexlify(value);
        });
        expect(Array.from(await helper.readAt(source, offset))).deep.eq(expected);
      }
    }
  });

  it("uses the full absolute position without uint32 narrowing or bounds checks", async () => {
    const helper = await deploy("CursorRawReadersCurrent");
    for (const width of widths) {
      const method = "read" + width;
      for (const abs of [1n << 32n, (1n << 32n) + 4n, 1n << 255n, ethers.MaxUint256]) {
        expect(await helper[method](abs)).eq("0x" + "00".repeat(width));
      }
      // Reading at zero exposes the call's selector, proving these are raw reads.
      const data = helper.interface.encodeFunctionData(method, [0]);
      expect(await helper[method](0)).eq(ethers.dataSlice(data, 0, width));
    }
  });
});
