import { expect } from "chai";
import { ethers } from "ethers";
import { mkdirSync, writeFileSync } from "node:fs";
import hre from "hardhat";
import { deploy } from "./helpers/setup.js";
import { concat, encodeBalanceBlock, encodeBytesBlock, encodeContextBlock } from "./helpers/blocks.js";

describe("Encoder cursor-last return order", function () {
  this.timeout(120_000);
  it("compares identical consumers with exact capacity and growth", async () => {
    const previous = await deploy("EncoderOrderPrevious"), current = await deploy("EncoderOrderCurrent");
    const account = ethers.toBeHex(7, 32), rows: any[] = [];
    for (const mode of [0, 1, 2, 3, 4]) {
      for (const size of mode === 0 ? [0] : [0, 32, 257]) {
        const state = "0x" + "ab".repeat(size), input = "0x" + "cd".repeat(size);
        const block = mode === 0 ? encodeBalanceBlock(account, 123n) : encodeContextBlock(account, state, input);
        for (const count of [1, 2, 4]) for (const grow of [false, true]) {
          const capacity = grow ? 0 : ethers.dataLength(block) * count;
          const args = [account, mode === 1 || mode === 2 ? encodeBytesBlock(state) : state,
            mode === 1 || mode === 2 ? encodeBytesBlock(input) : input, count, capacity, mode];
          const a = await previous.measure(...args), b = await current.measure(...args);
          expect(b[3]).eq(concat(...Array(count).fill(block)));
          expect(Array.from(b).slice(1)).deep.eq(Array.from(a).slice(1));
          expect(b[2] >> 128n).eq(0xabcdefn);
          expect(b[2] & 0xffffffffn).eq(BigInt(ethers.dataLength(block) * count));
          rows.push({ mode: ["balance", "contextMemory", "contextCursor", "wrapMemory", "wrapCursor"][mode],
            size, count, grow, previous: Number(a[0]), current: Number(b[0]), delta: Number(b[0] - a[0]) });
        }
      }
    }
    console.table(rows.filter(r => !r.grow && (r.mode === "balance" || r.size === 32)));
    const code = await Promise.all(["EncoderOrderPrevious", "EncoderOrderCurrent"].map(async name => {
      const bytecode = (await hre.artifacts.readArtifact(name)).deployedBytecode;
      const metadataLength = parseInt(bytecode.slice(-4), 16);
      return bytecode.slice(0, -(metadataLength + 2) * 2);
    }));
    mkdirSync(".npm-cache", { recursive: true });
    writeFileSync(".npm-cache/encoder-order-results.json", JSON.stringify({
      compiler: hre.config.solidity.profiles.default.compilers[0], rows,
      identicalExecutable: code[0] === code[1],
      executableBytes: code.map(value => (value.length - 2) / 2),
    }, null, 2) + "\n");
  });
});
