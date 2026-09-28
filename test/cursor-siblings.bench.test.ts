import { expect } from "chai";
import { ethers } from "ethers";
import { mkdirSync, writeFileSync } from "node:fs";
import hre from "hardhat";
import { deploy } from "./helpers/setup.js";
import { concat, encodeBlock, Keys } from "./helpers/blocks.js";
describe("Cursor sibling structure comparison", function () {
  this.timeout(120000);
  it("compares parent/child proof sharing for cursor and native calldata consumers", async () => {
    const rows: any[] = [];
    for (const kind of ["Relay", "Context"] as const) {
      const baseline = await deploy(`Cursor${kind}Baseline`);
      for (const variant of ["Baseline", "Composed", "Checked", "Fused", "RangeReference"]) {
        const h = await deploy(`Cursor${kind}${variant}`), artifact = await hre.artifacts.readArtifact(`Cursor${kind}${variant}`);
        const runtimeBytes = (artifact.deployedBytecode.length - 2) / 2;
        for (const [x, y] of [[0, 0], [0, 33], [33, 0], [1, 31], [33, 256]]) {
          const value = encodeBlock(Keys[kind], concat(kind === "Context" ? ethers.toBeHex(123, 32) : "0x", encodeBlock(Keys.Bytes, "0x" + "ab".repeat(x)), encodeBlock(Keys.Bytes, "0x" + "cd".repeat(y))));
          for (const method of ["measureCursor", "measureData"])
            for (const count of [1, 32, 128]) {
              const source = concat(...Array(count).fill(value)), a = await baseline[method](source), b = await h[method](source);
              expect(b[1]).eq(a[1]);
              expect(b[2]).eq(a[2]);
              expect(b[2] >> 64n).eq(0xa5n);
              rows.push({ kind, variant, x, y, method, count, gas: Number(b[0]), runtimeBytes });
            }
        }
      }
    }
    const slopes = rows.filter(r => r.count === 128).map(r => {
      const same = (s: any) => s.kind === r.kind && s.variant === r.variant && s.x === r.x && s.y === r.y && s.method === r.method;
      const one = rows.find(s => same(s) && s.count === 1), mid = rows.find(s => same(s) && s.count === 32), perBlock = (r.gas - one.gas) / 127;
      if (r.method === "measureCursor")
        expect((r.gas - mid.gas) / 96).eq(perBlock);
      return { kind: r.kind, variant: r.variant, x: r.x, y: r.y, method: r.method, perBlock, runtimeBytes: r.runtimeBytes };
    });
    console.table(slopes.filter(r => r.x === 33 && r.y === 256));
    mkdirSync(".npm-cache", { recursive: true });
    writeFileSync(".npm-cache/cursor-siblings-results.json", JSON.stringify({ compiler: hre.config.solidity.profiles.default.compilers[0], rows, slopes }, null, 2) + "\n");
  });
});
