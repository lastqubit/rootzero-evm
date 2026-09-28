import { expect } from "chai";
import { mkdirSync, writeFileSync } from "node:fs";
import hre from "hardhat";
import { deploy } from "./helpers/setup.js";
import { concat, encodeBlock, Keys } from "./helpers/blocks.js";

describe("Cursor unpack structure comparison", function () {
  this.timeout(120_000);
  it("compares composed, fused and end-only validation with runtime and constant keys", async () => {
    const variants = ["Baseline", "Composed", "Fused", "End", "BalanceBaseline", "BalanceComposed", "BalanceFused", "BalanceDirect", "RangeReference", "BalanceRangeReference", "FusedReference", "BalanceFusedReference"];
    const rows: any[] = [];
    const block = encodeBlock(Keys.Balance, "0x" + "ab".repeat(32) + "12".repeat(32));
    const baseline = await deploy("CursorUnpackBaseline");
    for (const variant of variants) {
      const helper = await deploy(`CursorUnpack${variant}`);
      const artifact = await hre.artifacts.readArtifact(`CursorUnpack${variant}`);
      const runtimeBytes = (artifact.deployedBytecode.length - 2) / 2;
      for (const method of ["measure", "measureValues"]) for (const count of [1, 32, 128]) {
        const source = concat(...Array(count).fill(block));
        const a = await baseline[method](source, Keys.Balance);
        const b = await helper[method](source, Keys.Balance);
        expect(b[1]).eq(a[1]); expect(b[2]).eq(a[2]);
        expect(b[2] >> 64n).eq(0xa5n);
        rows.push({ variant, method, count, gas: Number(b[0]), runtimeBytes });
      }
    }
    const slopes = rows.filter(r => r.count === 128).map(r => {
      const one = rows.find(s => s.variant === r.variant && s.method === r.method && s.count === 1);
      const middle = rows.find(s => s.variant === r.variant && s.method === r.method && s.count === 32);
      const perBlock = (r.gas - one.gas) / 127;
      expect((r.gas - middle.gas) / 96).eq(perBlock);
      return { variant: r.variant, method: r.method, perBlock, runtimeBytes: r.runtimeBytes };
    });
    console.table(slopes);
    const compiler = hre.config.solidity.profiles.default.compilers[0];
    const configuration = { version: compiler.version, settings: compiler.settings };
    mkdirSync(".npm-cache", { recursive: true });
    writeFileSync(`.npm-cache/cursor-unpack-results${compiler.settings.viaIR ? "-ir" : ""}.json`,
      JSON.stringify({ configuration, rows, slopes }, null, 2) + "\n");
  });
});
