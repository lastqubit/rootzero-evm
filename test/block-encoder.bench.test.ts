import { expect } from "chai";
import { ethers } from "ethers";
import { mkdirSync, writeFileSync } from "node:fs";
import hre from "hardhat";
import { deploy } from "./helpers/setup.js";
import { encodeContextBlock, encodeStateBlock, encodeInputBlock } from "./helpers/blocks.js";

describe("Encoder context benchmark", function () {
  this.timeout(120_000);
  it("compares copying complete children with rebuilding their headers", async () => {
    const payload = await deploy("TestBlockEncoder"), blocks = await deploy("TestBlockEncoderCopy");
    const payloadWriter = await deploy("TestBlockWriter"), blocksWriter = await deploy("TestBlockWriterCopy");
    const account = ethers.toBeHex(7n, 32), rows: any[] = [];
    for (const memory of [false, true]) for (const [a, b] of [[0, 0], [1, 1], [23, 24], [24, 25], [31, 32], [33, 65], [257, 2048]]) {
      const state = "0x" + "ab".repeat(a), input = "0x" + "cd".repeat(b);
      const expected = encodeContextBlock(account, state, input);
      for (const count of [1, 16]) for (const writer of [false, true]) {
        const before = writer
          ? await payloadWriter.measureWrite(account, state, input, count, 3, memory)
          : await payload.measure(account, state, input, count, memory);
        const after = writer
          ? await blocksWriter.measureWrite(account, encodeStateBlock(state), encodeInputBlock(input), count, 3, memory)
          : await blocks.measure(account, encodeStateBlock(state), encodeInputBlock(input), count, memory);
        for (const result of [before, after]) {
          expect(writer ? ethers.dataSlice(result[2], 3, 3 + 56 + a + b) : result[2]).eq(expected);
        }
        expect(after[1]).eq(before[1]);
        rows.push({ memory, writer, stateSize: a, inputSize: b, count, payload: Number(before[0]), blocks: Number(after[0]), delta: Number(after[0] - before[0]) });
      }
    }
    console.table(rows.filter(r => r.count === 16));
    mkdirSync(".npm-cache", { recursive: true });
    writeFileSync(".npm-cache/block-encoder-copy-results.json", JSON.stringify({ compiler: hre.config.solidity.profiles.default.compilers[0], rows }, null, 2) + "\n");
  });
  it("compares cursor and memory overloads with the existing factories", async () => {
    const old = await deploy("TestBlockEncoderPrevious"), current = await deploy("TestBlockEncoder");
    const oldWriter = await deploy("TestBlockWriterPrevious"), currentWriter = await deploy("TestBlockWriter");
    const account = ethers.toBeHex(7n, 32), rows: any[] = [];
    for (const memorySource of [false, true]) for (const [stateSize, inputSize] of [[0, 0], [0, 33], [33, 0], [1, 1], [31, 32], [33, 65], [257, 2048]]) {
      const state = "0x" + "ab".repeat(stateSize), input = "0x" + "cd".repeat(inputSize);
      const expected = encodeContextBlock(account, state, input);
      for (const count of [1, 16]) {
        const a = await old.measure(account, state, input, count, memorySource);
        const b = await current.measure(account, state, input, count, memorySource);
        expect(a[2]).eq(expected); expect(b[2]).eq(expected);
        expect(b[1]).eq(a[1]); // Owned leading log word replaces the baseline's retained scratch word.
        rows.push({ memorySource, stateSize, inputSize, count, old: Number(a[0]), current: Number(b[0]), delta: Number(b[0] - a[0]), allocated: Number(b[1]) });
        const wa = await oldWriter.measureWrite(account, state, input, count, 3, memorySource);
        const wb = await currentWriter.measureWrite(account, state, input, count, 3, memorySource);
        expect(wb[2]).eq(wa[2]);
        expect(ethers.dataSlice(wb[2], 3, 3 + 56 + stateSize + inputSize)).eq(expected);
        expect(wa[1]).eq(0n); expect(wb[1]).eq(0n);
        rows.push({ writer: true, memorySource, stateSize, inputSize, count, old: Number(wa[0]), current: Number(wb[0]), delta: Number(wb[0] - wa[0]), allocated: Number(wb[1]) });
      }
    }
    console.table(rows.filter(r => r.count === 16));
    mkdirSync(".npm-cache", { recursive: true });
    writeFileSync(".npm-cache/block-encoder-results.json", JSON.stringify({ compiler: hre.config.solidity.profiles.default.compilers[0], rows }, null, 2) + "\n");
  });
});
