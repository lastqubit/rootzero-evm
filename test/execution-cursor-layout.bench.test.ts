import { expect } from "chai";
import { mkdirSync, writeFileSync } from "node:fs";
import hre from "hardhat";
import { deploy } from "./helpers/setup.js";
import { layoutFixture, layoutModes } from "./helpers/execution-cursor-layout.js";

describe("Execution cursor layout benchmark", function () {
  this.timeout(120_000);
  it("compares packed decoders and independent input/state cursors using the same codec", async () => {
    const packed = await deploy("ExecutionCursorLayoutPacked"), split = await deploy("ExecutionCursorLayoutSplit");
    const alternatives = await Promise.all(["PackedPosition", "PackedDelta"].map(async name => ({
      name, helper: await deploy(`ExecutionCursorLayout${name}`),
    })));
    const alternativesRows: any[] = [];
    const rows: any[] = [];
    for (let mode = 0; mode < layoutModes.length; ++mode) for (const includeSetup of [false, true]) {
      for (const count of [0, 1, 4, 16, 64, 128]) {
        const f = layoutFixture(mode, count);
        const a = await packed.measure(f.input, f.state, mode, includeSetup, 3, f.seed);
        const b = await split.measure(f.input, f.state, mode, includeSetup, 3, f.seed);
        for (const r of [a, b]) {
          expect(r[1]).eq(f.checksum); expect(r[2]).eq(BigInt(count));
          for (const cur of [r[3], r[4]]) {
            expect(cur & 0xffffffffn).eq((cur >> 32n) & 0xffffffffn);
            expect(cur >> 64n).eq(1n);
          }
        }
        expect(Array.from(a).slice(1)).deep.eq(Array.from(b).slice(1));
        for (const alternative of alternatives) {
          const r = await alternative.helper.measure(f.input, f.state, mode, includeSetup, 3, f.seed);
          expect(Array.from(r).slice(1)).deep.eq(Array.from(b).slice(1));
          alternativesRows.push({ variant: alternative.name, mode: layoutModes[mode], includeSetup, count,
            gas: Number(r[0]), deltaVsSplit: Number(r[0] - b[0]) });
        }
        rows.push({ mode: layoutModes[mode], includeSetup, count, packed: Number(a[0]), split: Number(b[0]), delta: Number(b[0] - a[0]) });
      }
    }
    const bytes: Record<string, number> = {};
    for (const variant of ["Packed", "PackedPosition", "PackedDelta", "Split"]) {
      const a = await hre.artifacts.readArtifact(`ExecutionCursorLayout${variant}`);
      bytes[variant] = (a.deployedBytecode.length - 2) / 2;
    }
    const slopes = rows.filter(r => r.count === 128).map(r => {
      const one = rows.find(x => x.mode === r.mode && x.includeSetup === r.includeSetup && x.count === 1);
      const middle = rows.find(x => x.mode === r.mode && x.includeSetup === r.includeSetup && x.count === 16);
      const packed = (r.packed - one.packed) / 127, split = (r.split - one.split) / 127;
      expect((r.packed - middle.packed) / 112).eq(packed);
      expect((r.split - middle.split) / 112).eq(split);
      return { mode: r.mode, includeSetup: r.includeSetup, packed, split, delta: split - packed };
    });
    console.table(rows.filter(r => r.count === 0 || r.count === 16));
    console.table(slopes); console.table(bytes);
    console.table(alternativesRows.filter(r => r.includeSetup && r.count === 16));
    mkdirSync(".npm-cache", { recursive: true });
    writeFileSync(".npm-cache/execution-cursor-layout-results.json", JSON.stringify({
      compiler: hre.config.solidity.profiles.default.compilers[0], bytes, rows, slopes, alternativesRows,
    }, null, 2) + "\n");
  });
});
