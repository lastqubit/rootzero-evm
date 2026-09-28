import { expect } from "chai";
import { ethers } from "ethers";
import { deploy } from "./helpers/setup.js";
import { concat } from "./helpers/blocks.js";
const mask = (a: bigint, b: bigint) => [a === b, a !== b, a < b, a <= b, a > b, a >= b]
  .reduce((bits, result, i) => bits | (result ? 1n << BigInt(i) : 0n), 0n);

describe("CursorBlocks unchecked comparisons", function () {
  let helper: any;
  before(async () => { helper = await deploy("CursorCompareHelpers"); });
  it("compares full-width unsigned words with values and other unaligned positions", async () => {
    const values = [0n, 1n, (1n << 128n) - 1n, 1n << 128n, (1n << 255n) - 1n, 1n << 255n, ethers.MaxUint256];
    for (const a of values) for (const b of values) {
      const source = concat("0xabcdef", ethers.toBeHex(a, 32), "0x12", ethers.toBeHex(b, 32));
      expect(await helper.compareValue(source, 3, b)).eq(mask(a, b));
      expect(await helper.compareAt(source, 3, 36)).eq(mask(a, b));
      expect(await helper.compareAt(source, 36, 3)).eq(mask(b, a));
      expect(await helper.compareAt(source, 3, 3)).eq(mask(a, a));
    }
  });
  it("handles overlapping words and EVM zero-padding without enforcing slice bounds", async () => {
    const source = "0x" + "1234567890abcdef".repeat(8);
    const a = BigInt(ethers.dataSlice(source, 0, 32)), b = BigInt(ethers.dataSlice(source, 1, 33));
    expect(await helper.compareAt(source, 0, 1)).eq(mask(a, b));
    const partial = "0x123456", padded = BigInt(partial + "00".repeat(29));
    expect(await helper.compareValue(partial, 0, padded)).eq(mask(padded, padded));
    expect(await helper.compareAt(partial, 0, 3)).eq(mask(padded, 0n));
    const absolute = (1n << 32n) + 4n;
    // Narrowing either absolute position would instead read nonzero ABI words.
    expect(Array.from(await helper.compareAbsolute(absolute, ethers.MaxUint256, 0))).deep.eq([mask(0n, 0n), mask(0n, 0n)]);
    expect(Array.from(await helper.compareAbsolute(ethers.MaxUint256, absolute, ethers.MaxUint256))).deep.eq([mask(0n, ethers.MaxUint256), mask(0n, 0n)]);
  });
});
