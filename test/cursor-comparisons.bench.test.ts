import { expect } from "chai";
import { ethers } from "ethers";
import { mkdirSync, writeFileSync } from "node:fs";
import hre from "hardhat";
import { deploy } from "./helpers/setup.js";
import { concat } from "./helpers/blocks.js";

describe("Cursor comparison primitive benchmark", function () {
  this.timeout(120_000);
  it("compares all six predicates with equivalent read-then-compare consumers", async () => {
    const baseline = await deploy("CursorCompareReads"), helper = await deploy("CursorCompareHelpers"), rows: any[] = [];
    for (const [a, b] of [[0n, 0n], [1n, 2n], [2n, 1n], [1n << 255n, ethers.MaxUint256]]) {
      for (const method of ["measureValue", "measureAt"]) for (const count of [1, 32, 128]) {
        const source = concat(...(method === "measureAt" ? [ethers.toBeHex(b, 32)] : []), ...Array(count).fill(ethers.toBeHex(a, 32)));
        const args = method === "measureAt" ? [source] : [source, b];
        const old = await baseline[method](...args), next = await helper[method](...args);
        expect(next[1]).eq(old[1]);
        rows.push({ a: String(a), b: String(b), method, count, baseline: Number(old[0]), helpers: Number(next[0]) });
      }
    }
    const compiler = hre.config.solidity.profiles.default.compilers[0];
    if (compiler.settings.viaIR) for (const row of rows) expect(row.helpers).eq(row.baseline);
    const slopes = rows.filter(r => r.count === 128).map(r => {
      const one = rows.find(s => s.a === r.a && s.b === r.b && s.method === r.method && s.count === 1);
      const mid = rows.find(s => s.a === r.a && s.b === r.b && s.method === r.method && s.count === 32);
      const baseline = (r.baseline - one.baseline) / 127, helpers = (r.helpers - one.helpers) / 127;
      expect((r.helpers - mid.helpers) / 96).eq(helpers);
      return { a: r.a, b: r.b, method: r.method, baseline, helpers };
    });
    console.table(slopes);
    mkdirSync(".npm-cache", { recursive: true });
    writeFileSync(".npm-cache/cursor-comparisons-results.json", JSON.stringify({ compiler, rows, slopes }, null, 2) + "\n");
  });
});
