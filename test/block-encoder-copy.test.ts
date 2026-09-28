import { expect } from "chai";
import { ethers } from "ethers";
import { deploy } from "./helpers/setup.js";
import { concat, encodeBytesBlock, encodeContextBlock } from "./helpers/blocks.js";

describe("Historical complete-child creator and writer copies", () => {
  it("preserves the frozen complete-child creator baseline", async () => {
    const helper = await deploy("TestBlockEncoderCopy");
    const account = ethers.toBeHex(7n, 32);
    for (const [a, b] of [[0, 0], [0, 1], [1, 0], [23, 24], [24, 25], [31, 32], [33, 65], [257, 2048]]) {
      const state = "0x" + "ab".repeat(a), input = "0x" + "cd".repeat(b);
      const stateBlock = encodeBytesBlock(state), inputBlock = encodeBytesBlock(input);
      const source = concat("0x112233", stateBlock, inputBlock, "0x445566");
      const expected = encodeContextBlock(account, state, input);
      for (const memory of [false, true]) for (const metadata of [0n, ethers.MaxUint256]) {
        const [output, stateCur, inputCur] = await helper.inspect(account, source, 3, 11 + a, 19 + a + b, metadata, memory);
        expect(output).eq(expected);
        expect(stateCur >> 64n).eq(metadata >> 64n);
        expect(inputCur >> 64n).eq(metadata >> 64n);
        expect(((stateCur >> 32n) & 0xffffffffn) - (stateCur & 0xffffffffn)).eq(BigInt(8 + a));
        expect(((inputCur >> 32n) & 0xffffffffn) - (inputCur & 0xffffffffn)).eq(BigInt(8 + b));
      }
      expect(await helper.reencode(expected)).eq(expected);
    }
  });

  it("writes without allocation or scratch, preserving adjacent bytes and memory sources", async () => {
    const helper = await deploy("TestBlockWriterCopy");
    const account = ethers.toBeHex(7n, 32);
    for (const [a, b] of [[0, 0], [0, 1], [1, 0], [23, 24], [24, 25], [31, 32], [33, 65], [257, 2048]]) {
      const state = "0x" + "ab".repeat(a), input = "0x" + "cd".repeat(b);
      const expected = encodeContextBlock(account, state, input);
      for (const memory of [false, true]) for (const offset of [0, 1, 31, 32]) {
        const [, allocated, output] = await helper.measureWrite(account, encodeBytesBlock(state), encodeBytesBlock(input), 2, offset, memory);
        expect(allocated).eq(0n);
        expect(output).eq(concat("0x" + "ef".repeat(offset), expected, "0x" + "ef".repeat(32)));
      }
    }
  });
});
