import { expect } from "chai";
import { ethers } from "ethers";
import { mkdirSync, writeFileSync } from "node:fs";
import hre from "hardhat";
import { deploy } from "./helpers/setup.js";
import { concat, encodeAmountBlock, encodeBalanceBlock, encodeBalanceConstraintsBlock, encodeContextBlock } from "./helpers/blocks.js";

describe("BALANCE encoder gas", function () {
  this.timeout(120_000);
  it("compares the frozen offset BALANCE writer and current creator with Blocks", async () => {
    const helpers = await Promise.all(["TestBalanceEncoderPrevious", "TestBalanceEncoder"].map(name => deploy(name)));
    const asset = ethers.toBeHex(1, 32), rows: any[] = [];
    for (const count of [1, 4, 16, 64]) for (const factory of [false, true]) {
      const results: any[] = [];
      for (const helper of helpers) {
        const r = await helper.measure(asset, 100n, count, factory);
        expect(r[2]).eq(factory ? encodeBalanceBlock(asset, 100n) : concat(...Array(count).fill(encodeBalanceBlock(asset, 100n))));
        results.push(r);
      }
      expect(results[1][1]).eq(factory ? results[0][1] - 32n * BigInt(count) : 0n);
      rows.push({ count, factory, old: Number(results[0][0]), current: Number(results[1][0]) });
    }
    console.table(rows);
    mkdirSync(".npm-cache", { recursive: true });
    writeFileSync(".npm-cache/balance-encoder-results.json", JSON.stringify({ compiler: hre.config.solidity.profiles.default.compilers[0], rows }, null, 2));
  });

  it("compares real checkBalance and debitAccount commands with only the output encoder changed", async () => {
    const hosts = await Promise.all(["TestBalanceEncoderCommandsPrevious", "TestBalanceEncoderCommands"].map(name => deploy(name)));
    const account = ethers.toBeHex(3, 32), asset = ethers.toBeHex(1, 32), rows: any[] = [];
    let debited = 0n;
    for (const count of [0, 1, 4, 16, 64]) for (const command of ["checkBalance", "debitAccount"]) {
      const state = concat(...Array(count).fill(encodeBalanceBlock(asset, 100n)));
      const input = concat(...Array(count).fill(command === "checkBalance" ? encodeBalanceConstraintsBlock(asset, 90n, 110n) : encodeAmountBlock(asset, 100n)));
      const context = encodeContextBlock(account, command === "checkBalance" ? state : "0x", input);
      const execution: number[] = [], receipt: number[] = [];
      for (const host of hosts) {
        expect(Array.from(await host[command].staticCall(context))).deep.eq([state, 0n]);
        const measured = await host.measure.staticCall(context, command === "debitAccount");
        expect(Array.from(measured).slice(1)).deep.eq([state, 0n]);
        execution.push(Number(measured[0]));
        const tx = await (await host[command](context)).wait();
        receipt.push(Number(tx.gasUsed));
      }
      if (command === "debitAccount") debited += BigInt(count) * 100n;
      for (const host of hosts) expect(await host.debited(account, asset)).eq(debited);
      rows.push({ command, count, old: execution[0], current: execution[1], delta: execution[1] - execution[0], oldReceipt: receipt[0], currentReceipt: receipt[1] });
    }
    console.table(rows);
    writeFileSync(".npm-cache/balance-encoder-command-results.json", JSON.stringify({ compiler: hre.config.solidity.profiles.default.compilers[0], rows }, null, 2));
  });
});
