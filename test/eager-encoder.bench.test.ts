import { expect } from "chai";
import { ethers } from "ethers";
import { mkdirSync, writeFileSync } from "node:fs";
import hre from "hardhat";
import { deploy } from "./helpers/setup.js";
import { concat, encodeBalanceBlock, encodeContextBlock, encodeStateBlock, encodeInputBlock } from "./helpers/blocks.js";

describe("Short encoder lifecycle gas", function () {
  this.timeout(120_000);
  it("includes initialization, allocation, 0–4 writes, and finish with exact capacity", async () => {
    const names = ["LazyRelative", "EagerRelative", "EagerAbsolute"];
    const helpers = await Promise.all(names.map(name => deploy(`Test${name}Encoder`)));
    const account = ethers.toBeHex(7, 32), rows: any[] = [];
    for (const count of [0, 1, 2, 3, 4]) for (const grow of [false, true]) {
      const row: any = { kind: "balance", size: 0, count, grow };
      for (let i = 0; i < helpers.length; ++i) {
        const [gas, output] = await helpers[i].balances(account, 123, count, grow ? 0 : 72 * count);
        expect(output).eq(concat(...Array(count).fill(encodeBalanceBlock(account, 123n))));
        row[names[i]] = Number(gas);
      }
      rows.push(row);
    }
    for (const mode of [0, 1, 2, 3]) for (const size of [0, 1, 32, 257]) for (const count of [1, 2, 3, 4]) for (const grow of [false, true]) {
      const state = "0x" + "ab".repeat(size), input = "0x" + "cd".repeat(size);
      const block = encodeContextBlock(account, state, input);
      const row: any = { kind: ["contextMemory", "contextCursor", "wrapMemory", "wrapCursor"][mode], size, count, grow };
      for (let i = 0; i < helpers.length; ++i) {
        const [gas, output] = await helpers[i].contexts(account, mode < 2 ? encodeStateBlock(state) : state,
          mode < 2 ? encodeInputBlock(input) : input, count, grow ? 0 : ethers.dataLength(block) * count, mode);
        expect(output).eq(concat(...Array(count).fill(block)));
        row[names[i]] = Number(gas);
      }
      rows.push(row);
    }
    console.table(rows.filter(r => !r.grow && (r.kind === "balance" || r.size === 32)));
    mkdirSync(".npm-cache", { recursive: true });
    writeFileSync(".npm-cache/eager-encoder-results.json", JSON.stringify({ compiler: hre.config.solidity.profiles.default.compilers[0], rows }, null, 2));
  });
});
