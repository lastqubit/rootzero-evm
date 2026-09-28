import { expect } from "chai";
import { ethers } from "ethers";
import { mkdirSync, writeFileSync } from "node:fs";
import hre from "hardhat";
import { deploy } from "./helpers/setup.js";
import { concat, encodeBalanceBlock, encodeBalanceConstraintsBlock, encodeContextBlock } from "./helpers/blocks.js";

describe("Production command balance decoder gas", function () {
  this.timeout(120_000);
  it("compares real checkBalance and withdraw commands with only their balance decoder changed", async () => {
    const previous = await deploy("CommandBalancePrevious"), current = await deploy("CommandBalanceCurrent");
    const account = ethers.toBeHex(3n, 32), asset = ethers.toBeHex(1n, 32);
    const rows: { command: string; count: number; previous: number; current: number; saved: number; previousExecution: number; currentExecution: number; executionSaved: number; calldataFloor: number }[] = [];
    let delivered = 0n;
    for (const count of [0, 1, 4, 16, 64]) {
      const state = concat(...Array(count).fill(encodeBalanceBlock(asset, 100n)));
      const constraints = concat(...Array(count).fill(encodeBalanceConstraintsBlock(asset, 90n, 110n)));
      for (const command of ["checkBalance", "withdraw"]) {
        const context = encodeContextBlock(account, state, command === "checkBalance" ? constraints : "0x");
        // EIP-7623: transaction gas cannot fall below this calldata-dependent floor.
        const data = previous.interface.encodeFunctionData(command, [context]);
        const calldataFloor = 21_000 + 10 * ethers.getBytes(data).reduce((tokens, byte) => tokens + (byte === 0 ? 1 : 4), 0);
        const gas: number[] = [], execution: number[] = [];
        for (const host of [previous, current]) {
          expect(Array.from(await host[command].staticCall(context))).deep.eq([command === "checkBalance" ? state : "0x", 0n]);
          const measured = await host.measure.staticCall(context, command === "withdraw");
          expect(Array.from(measured).slice(1)).deep.eq([command === "checkBalance" ? state : "0x", 0n]);
          execution.push(Number(measured[0]));
          const receipt = await (await host[command](context)).wait();
          gas.push(Number(receipt.gasUsed));
        }
        rows.push({ command, count, previous: gas[0], current: gas[1], saved: gas[0] - gas[1],
          previousExecution: execution[0], currentExecution: execution[1], executionSaved: execution[0] - execution[1], calldataFloor });
      }
      delivered += BigInt(count) * 100n;
      for (const host of [previous, current]) expect(await host.delivered(account, asset)).eq(delivered);
    }
    const bytes: Record<string, number> = {};
    for (const name of ["Previous", "Current"]) {
      const artifact = await hre.artifacts.readArtifact(`CommandBalance${name}`);
      bytes[name] = (artifact.deployedBytecode.length - 2) / 2;
    }
    console.table(rows); console.table(bytes);
    mkdirSync(".npm-cache", { recursive: true });
    writeFileSync(".npm-cache/command-balance-decoder-results.json", JSON.stringify({
      compiler: hre.config.solidity.profiles.default.compilers[0], rows, bytes,
      scope: "Transaction receipt gas; real command entrypoints, runner, output and storage-recording withdraw hook. No token transfer. Both hosts use split input/state cursors.",
    }, null, 2) + "\n");
  });
});
