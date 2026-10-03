import { expect } from "chai";
import { ethers } from "ethers";
import { mkdirSync, writeFileSync } from "node:fs";
import hre from "hardhat";
import { deploy } from "./helpers/setup.js";
import { concat, encodeBalanceBlock, encodeContextBlock, encodeStateBlock, encodeInputBlock } from "./helpers/blocks.js";

describe("Encoder buffer lifecycle gas", function () {
  this.timeout(120_000);
  it("compares existing capacity, first allocation, and repeated growth including finalization", async () => {
    const helpers = await Promise.all(["TestEncoderBufferPrevious", "TestEncoderBuffer"].map(name => deploy(name)));
    const account = ethers.toBeHex(7, 32), rows: any[] = [];
    for (const mode of [0, 1, 2, 3, 4]) for (const size of mode === 0 ? [0] : [0, 32, 257]) {
      const state = "0x" + "ab".repeat(size), input = "0x" + "cd".repeat(size);
      const block = mode === 0 ? encodeBalanceBlock(account, 123n) : encodeContextBlock(account, state, input);
      for (const count of [1, 4, 16, 64]) for (const scenario of ["warm", "allocate", "grow"]) {
        // Include the old writer's header scratch in both hints to isolate the
        // reservation implementation when no growth is required.
        const capacity = scenario === "grow" ? 0 : ethers.dataLength(block) * count + 24;
        const results: any[] = [];
        for (const helper of helpers) {
          const r = await helper.measure(account, mode === 1 || mode === 2 ? encodeStateBlock(state) : state,
            mode === 1 || mode === 2 ? encodeInputBlock(input) : input, count, capacity, mode, scenario === "warm");
          expect(r[3]).eq(concat(...Array(count).fill(block)));
          results.push(r);
        }
        rows.push({ mode: ["balance", "contextMemory", "contextCursor", "wrapMemory", "wrapCursor"][mode], size, count, scenario,
          old: Number(results[0][0]), current: Number(results[1][0]), delta: Number(results[1][0] - results[0][0]),
          oldMemory: Number(results[0][1]), currentMemory: Number(results[1][1]) });
      }
    }
    const balances: any[] = [];
    for (const count of [1, 4, 16, 64]) for (const scenario of ["warm", "allocate", "grow"]) {
      const capacity = scenario === "grow" ? 0 : 72 * count;
      const results: any[] = [];
      for (const helper of helpers) {
        const r = await helper.balances(account, 123, count, capacity, scenario === "warm");
        expect(r[1]).eq(concat(...Array(count).fill(encodeBalanceBlock(account, 123n))));
        results.push(r);
      }
      balances.push({ count, scenario, old: Number(results[0][0]), current: Number(results[1][0]), delta: Number(results[1][0] - results[0][0]) });
    }
    console.table(rows.filter(r => r.count === 4));
    console.table(balances);
    mkdirSync(".npm-cache", { recursive: true });
    writeFileSync(".npm-cache/encoder-buffer-results.json", JSON.stringify({ compiler: hre.config.solidity.profiles.default.compilers[0], rows, balances }, null, 2));
  });
});
