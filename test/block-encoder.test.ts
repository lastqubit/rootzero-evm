import { expect } from "chai";
import { ethers } from "ethers";
import { deploy } from "./helpers/setup.js";
import "./helpers/matchers.js";
import { concat, encodeBytesBlock, encodeContextBlock } from "./helpers/blocks.js";

describe("Encoder context overloads", () => {
  it("chains every CONTEXT writer using its returned relative offset", async () => {
    const helper = await deploy("TestBlockEncoderNextOffsets");
    const account = ethers.toBeHex(7n, 32);
    for (const [a, b] of [[0, 0], [1, 0], [0, 1], [31, 33]]) {
      const state = "0x" + "ab".repeat(a), input = "0x" + "cd".repeat(b);
      const expected = encodeContextBlock(account, state, input);
      for (const wrap of [false, true]) for (const memory of [false, true]) {
        const [output, nextI] = await helper.chain(account, wrap ? state : encodeBytesBlock(state), wrap ? input : encodeBytesBlock(input), wrap, memory);
        expect(nextI).eq(BigInt(3 + 2 * ethers.dataLength(expected)));
        expect(ethers.dataSlice(output, 0, Number(nextI))).eq(concat("0xefefef", expected, expected));
        expect(ethers.dataSlice(output, Number(nextI) + 24)).eq("0x" + "ef".repeat(32));
      }
    }
  });
  it("composes a custom schema with a fixed word, wrapped payload, and intact child", async () => {
    const helper = await deploy("TestBlockEncoderComposition");
    const key = "0x11223344", word = ethers.toBeHex(42n, 32);
    for (const size of [0, 1, 23, 24, 31, 32, 33, 257]) {
      const payload = "0x" + "ab".repeat(size);
      const child = encodeBytesBlock("0x" + "cd".repeat(size));
      const body = concat(word, encodeBytesBlock(payload), child);
      const expected = concat(key, ethers.toBeHex(ethers.dataLength(body), 4), body);
      for (const memory of [false, true]) {
        const [output, written] = await helper.encode(key, word, payload, child, memory);
        expect(output).eq(expected);
        expect(written).eq(BigInt(ethers.dataLength(expected)));
      }
    }
  });
  it("cleans dirty allocation padding and preserves earlier outputs and sources", async () => {
    const helper = await deploy("TestBlockEncoderMemory");
    const account = ethers.toBeHex(7n, 32);
    for (const [a, b] of [[0, 0], [0, 1], [1, 0], [0, 8], [7, 1], [31, 32], [33, 65], [257, 2048]]) {
      const state = "0x" + "ab".repeat(a), input = "0x" + "cd".repeat(b);
      for (const memory of [false, true]) {
        const [first, second, cleanPadding] = await helper.inspect(account, state, input, memory);
        expect(first).eq(encodeContextBlock(account, state, input));
        expect(second).eq(encodeContextBlock(account, input, state));
        expect(cleanPadding).eq(true);
      }
    }
    await expect(helper.oversized()).to.be.revertedWithCustomError(helper, "ValueOverflow");
  });
  it("writes into reserved buffers without allocation or changes outside the block and scratch", async () => {
    const helper = await deploy("TestBlockWriter");
    const account = ethers.toBeHex(7n, 32);
    for (const [a, b] of [[0, 0], [0, 1], [1, 0], [1, 1], [23, 23], [24, 24], [31, 32], [33, 65], [257, 2048]]) {
      const state = "0x" + "ab".repeat(a), input = "0x" + "cd".repeat(b);
      const expected = encodeContextBlock(account, state, input);
      for (const memory of [false, true]) for (const offset of [0, 1, 31, 32]) {
        const [, allocated, output] = await helper.measureWrite(account, state, input, 2, offset, memory);
        expect(allocated).eq(0n);
        expect(ethers.dataSlice(output, 0, offset)).eq("0x" + "ef".repeat(offset));
        expect(ethers.dataSlice(output, offset, offset + 56 + a + b)).eq(expected);
        expect(ethers.dataSlice(output, offset + 56 + a + b + 24)).eq("0x" + "ef".repeat(32));
      }
    }
  });
  it("encodes only the remaining ranges, preserving cursors and ignoring metadata", async () => {
    const helper = await deploy("TestBlockEncoder");
    const account = ethers.toBeHex(7n, 32);
    for (const [a, b] of [[0, 0], [0, 33], [33, 0], [1, 1], [31, 32], [32, 31], [33, 65], [257, 2048]]) {
      const state = "0x" + "ab".repeat(a), input = "0x" + "cd".repeat(b);
      const source = concat("0x112233", state, input, "0x44556677");
      const expected = encodeContextBlock(account, state, input);
      for (const memory of [false, true]) for (const metadata of [0n, ethers.MaxUint256]) {
        const [output, stateCur, inputCur] = await helper.inspect(account, source, 3, 3 + a, 3 + a + b, metadata, memory);
        expect(output).eq(expected);
        expect(stateCur >> 64n).eq(metadata >> 64n);
        expect(inputCur >> 64n).eq(metadata >> 64n);
        expect(((stateCur >> 32n) & 0xffffffffn) - (stateCur & 0xffffffffn)).eq(BigInt(a));
        expect(((inputCur >> 32n) & 0xffffffffn) - (inputCur & 0xffffffffn)).eq(BigInt(b));
      }
      expect(await helper.reencode(expected)).eq(expected);
    }
  });
});
