import { expect } from "chai";
import { ethers } from "ethers";
import { mkdirSync, writeFileSync } from "node:fs";
import hre from "hardhat";
import { deploy } from "./helpers/setup.js";
import { concat, encodeBlock, Keys } from "./helpers/blocks.js";
describe("Cursor five-word structure comparison", function () {
  this.timeout(120000);
  it("compares packed composition, shared end validation and fused loads", async () => {
    const rows: any[] = [], baseline = await deploy("CursorWideBaseline");
    const block = encodeBlock(Keys.Position, concat(...[1, 2, 3, 4, 5].map(x => ethers.toBeHex(x, 32))));
    for (const variant of ["Baseline", "Composed", "Fused", "RangeReference"]) {
      const h = await deploy(`CursorWide${variant}`), artifact = await hre.artifacts.readArtifact(`CursorWide${variant}`), runtimeBytes = (artifact.deployedBytecode.length - 2) / 2;
      for (const method of ["measure", "measureValues"])
        for (const count of [1, 32, 128]) {
          const source = concat(...Array(count).fill(block)), a = await baseline[method](source, Keys.Position), b = await h[method](source, Keys.Position);
          expect(b[1]).eq(a[1]);
          expect(b[2]).eq(a[2]);
          expect(b[2] >> 64n).eq(0xa5n);
          rows.push({ variant, method, count, gas: Number(b[0]), runtimeBytes });
        }
    }
    const slopes = rows.filter(r => r.count === 128).map(r => {
      const one = rows.find(s => s.variant === r.variant && s.method === r.method && s.count === 1), mid = rows.find(s => s.variant === r.variant && s.method === r.method && s.count === 32), perBlock = (r.gas - one.gas) / 127;
      expect((r.gas - mid.gas) / 96).eq(perBlock);
      return { variant: r.variant, method: r.method, perBlock, runtimeBytes: r.runtimeBytes };
    });
    console.table(slopes);
    mkdirSync(".npm-cache", { recursive: true });
    writeFileSync(".npm-cache/cursor-wide-results.json", JSON.stringify({ compiler: hre.config.solidity.profiles.default.compilers[0], rows, slopes }, null, 2) + "\n");
  });
});
