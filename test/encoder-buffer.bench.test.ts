import { expect } from "chai";
import { ethers } from "ethers";
import { mkdirSync, writeFileSync } from "node:fs";
import hre from "hardhat";
import { deploy } from "./helpers/setup.js";
import { concat, encodeBalanceBlock, encodeContextBlock, encodeStateBlock, encodeInputBlock } from "./helpers/blocks.js";

describe("Encoder buffer lifecycle gas", function () {
  this.timeout(120_000);
  it("measures current writers from allocation through finalization with exact hints and growth", async () => {
    const helper = await deploy("TestEncoderBuffer");
    const account = ethers.toBeHex(7, 32);
    const rows: object[] = [];
    for (const mode of [0, 1, 2, 3, 4]) for (const size of mode === 0 ? [0] : [0, 32, 257]) {
      const state = "0x" + "ab".repeat(size), input = "0x" + "cd".repeat(size);
      const block = mode === 0 ? encodeBalanceBlock(account, 123n) : encodeContextBlock(account, state, input);
      for (const count of [0, 1, 16, 64]) for (const scenario of ["exact", "grow"]) {
        if (count === 0 && scenario === "grow") continue;
        const capacity = scenario === "grow" ? 0 : ethers.dataLength(block) * count;
        const result = await helper.measure(account,
          mode === 1 || mode === 2 ? encodeStateBlock(state) : state,
          mode === 1 || mode === 2 ? encodeInputBlock(input) : input,
          count, capacity, mode, false);
        expect(result[3]).eq(concat(...Array(count).fill(block)));
        rows.push({ mode: ["balance", "contextMemory", "contextCursor", "wrapMemory", "wrapCursor"][mode],
          size, count, scenario, gas: Number(result[0]), retainedBytes: Number(result[1]) });
      }
    }
    mkdirSync(".npm-cache", { recursive: true });
    writeFileSync(".npm-cache/encoder-buffer-results.json", JSON.stringify({
      compiler: hre.config.solidity.profiles.default.compilers[0], rows,
    }, null, 2) + "\n");
    console.table(rows);
  });
});
