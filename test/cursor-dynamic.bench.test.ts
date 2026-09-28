import { expect } from "chai";
import { ethers } from "ethers";
import { mkdirSync, writeFileSync } from "node:fs";
import hre from "hardhat";
import { deploy } from "./helpers/setup.js";
import { concat, encodeBlock, Keys } from "./helpers/blocks.js";

describe("Cursor dynamic structure comparison", function () {
  this.timeout(120_000);
  it("compares STEP unpackers for cursor and native calldata consumers", async () => {
    const rows: any[] = [];
    const baseline = await deploy("CursorDynamicBaseline");
    for (const variant of ["Baseline", "Composed", "Expected", "Fused", "RangeReference"]) {
      const helper = await deploy(`CursorDynamic${variant}`);
      const artifact = await hre.artifacts.readArtifact(`CursorDynamic${variant}`);
      const runtimeBytes = (artifact.deployedBytecode.length - 2) / 2;
      for (const length of [0, 1, 33, 256]) {
        const block = encodeBlock(Keys.Step, concat(ethers.toBeHex(1, 32), ethers.toBeHex(2, 32),
          encodeBlock(Keys.Bytes, "0x" + "ab".repeat(length))));
        for (const method of ["measureCursor", "measureData"]) for (const count of [1, 32, 128]) {
          const source = concat(...Array(count).fill(block));
          const a = await baseline[method](source), b = await helper[method](source);
          expect(b[1]).eq(a[1]); expect(b[2]).eq(a[2]); expect(b[2] >> 64n).eq(0xa5n);
          rows.push({ variant, length, method, count, gas: Number(b[0]), runtimeBytes });
        }
      }
    }
    const slopes = rows.filter(r => r.count === 128).map(r => {
      const one = rows.find(s => s.variant === r.variant && s.method === r.method && s.length === r.length && s.count === 1);
      const middle = rows.find(s => s.variant === r.variant && s.method === r.method && s.length === r.length && s.count === 32);
      const perBlock = (r.gas - one.gas) / 127;
      // Hashing expands memory; retain totals rather than asserting linear gas there.
      if (r.method === "measureCursor") expect((r.gas - middle.gas) / 96).eq(perBlock);
      return { variant: r.variant, length: r.length, method: r.method, perBlock, runtimeBytes: r.runtimeBytes };
    });
    const compiler = hre.config.solidity.profiles.default.compilers[0];
    if (compiler.settings.viaIR) for (const row of rows.filter(r => r.variant === "RangeReference")) {
      const fused = rows.find(r => r.variant === "Fused" && r.length === row.length && r.method === row.method && r.count === row.count);
      expect(row.gas, `shared primitives vs fused: ${row.method}/${row.length}/${row.count}`).at.most(fused.gas);
    }
    console.table(slopes);
    mkdirSync(".npm-cache", { recursive: true });
    writeFileSync(".npm-cache/cursor-dynamic-results.json", JSON.stringify({ compiler, rows, slopes }, null, 2) + "\n");
  });
});
