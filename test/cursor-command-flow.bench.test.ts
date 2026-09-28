import { expect } from "chai";
import { mkdirSync, writeFileSync } from "node:fs";
import hre from "hardhat";
import { deploy } from "./helpers/setup.js";
import { size } from "./helpers/cursor-consumers.js";
import { commandFlow } from "./helpers/cursor-command-flow.js";

describe("Packed cursor command flow benchmark", function () {
  this.timeout(120_000);
  it("chains updated cursors through nested loops, dispatch, unpack and expect calls", async () => {
    const old = await deploy("CursorCommandFlowOld"), current = await deploy("CursorCommandFlowNew");
    const rows: { steps: number; children: number; old: number; current: number; delta: number }[] = [];
    for (const children of [0, 1, 4, 16]) for (const steps of [2, 16, 64]) {
      const fixture = commandFlow(steps, children);
      const results: number[] = [];
      for (const helper of [old, current]) {
        const r = await helper.measure(fixture.source, size(fixture.source), 0, 0xa5n << 64n);
        expect(r[1]).eq(fixture.sum);
        expect(r[2]).eq(fixture.records);
        const end = r[4] + BigInt(size(fixture.source));
        expect(r[3]).eq(end | (end << 32n) | (0xa5n << 64n));
        results.push(Number(r[0]));
      }
      rows.push({ steps, children, old: results[0], current: results[1], delta: results[1] - results[0] });
    }
    const bytes: Record<string, number> = {};
    for (const variant of ["Old", "New"]) {
      const artifact = await hre.artifacts.readArtifact(`CursorCommandFlow${variant}`);
      bytes[variant] = (artifact.deployedBytecode.length - 2) / 2;
    }
    console.table(rows);
    console.table(bytes);
    mkdirSync(".npm-cache", { recursive: true });
    writeFileSync(".npm-cache/cursor-command-flow-results.json", JSON.stringify({
      compiler: hre.config.solidity.profiles.default.compilers[0], bytes, rows,
    }, null, 2) + "\n");
  });
});
