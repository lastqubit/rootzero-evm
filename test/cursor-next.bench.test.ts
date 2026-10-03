import { expect } from "chai";
import { ethers } from "ethers";
import { mkdirSync, writeFileSync } from "node:fs";
import hre from "hardhat";
import { deploy } from "./helpers/setup.js";
import { concat, encodeBlock, Keys } from "./helpers/blocks.js";
describe("Advanced cursor return comparison", function () {
  this.timeout(120_000);
  it("compares complete consuming loops with selected ranges and returned stream cursors", async () => {
    const rows: any[] = [];
    const words = concat(ethers.toBeHex(1, 32), ethers.toBeHex(2, 32));
    for (const kind of ["Balance", "Step"]) {
      const baseline = await deploy(`CursorNext${kind}Selected`);
      for (const variant of ["Selected", "Composed", "Direct", "Current", "LoopSelected", "LoopDirect", "LoopCurrent"]) {
        const helper = await deploy(`CursorNext${kind}${variant}`), artifact = await hre.artifacts.readArtifact(`CursorNext${kind}${variant}`);
        const runtimeBytes = (artifact.deployedBytecode.length - 2) / 2;
        for (const length of kind === "Step" ? [0, 1, 33, 256] : [64]) {
          const block = kind === "Balance" ? encodeBlock(Keys.Balance, words) : encodeBlock(Keys.Step, concat(words, encodeBlock(Keys.Input, "0x" + "ab".repeat(length))));
          for (const method of kind === "Balance" ? ["measure", "measureDiscard"] : ["measure", "measureData"]) for (const count of [1, 32, 128]) {
            const source = concat(...Array(count).fill(block)), a = await baseline[method](source), b = await helper[method](source);
            expect(b[1]).eq(a[1]); expect(b[2]).eq(a[2]); expect(b[2] >> 64n).eq(0xa5n);
            rows.push({ kind, variant, length, method, count, gas: Number(b[0]), runtimeBytes });
          }
        }
      }
    }
    const slopes = rows.filter(r => r.count === 128).map(r => {
      const same = (s: any) => s.kind === r.kind && s.variant === r.variant && s.length === r.length && s.method === r.method;
      const one = rows.find(s => same(s) && s.count === 1), middle = rows.find(s => same(s) && s.count === 32);
      const perBlock = (r.gas - one.gas) / 127;
      if (r.method !== "measureData") expect((r.gas - middle.gas) / 96).eq(perBlock);
      return { kind: r.kind, variant: r.variant, length: r.length, method: r.method, perBlock, runtimeBytes: r.runtimeBytes };
    });
    console.table(slopes);
    mkdirSync(".npm-cache", { recursive: true });
    writeFileSync(".npm-cache/cursor-next-results.json", JSON.stringify({ compiler: hre.config.solidity.profiles.default.compilers[0], rows, slopes }, null, 2) + "\n");
  });
});
