import { expect } from "chai";
import { mkdirSync, writeFileSync } from "node:fs";
import hre from "hardhat";
import { deploy } from "./helpers/setup.js";
import { concat, encodeBlock, exactSpec, rangedSpec, Keys } from "./helpers/blocks.js";

describe("Blocks versus CursorBlocks", function () {
  this.timeout(120_000);
  it("compares bounded tuple and packed producers with equivalent stream consumers", async () => {
    const rows: any[] = [];
    const block = encodeBlock(Keys.Bytes, "0x" + "ab".repeat(32));
    for (const kind of ["Spec", "Key", "Fixed", "FixedExpected", "Peek", "Enter", "Prefix", "EnterFused", "PrefixFused", "PrefixLen", "EnterPrevious", "PrefixPrevious",
      "SpecFusedReference", "KeyFusedReference", "FixedFusedReference", "PeekFusedReference", "EnterFusedReference", "PrefixFusedReference"]) {
      const baseline = await deploy(`CursorBlocks${kind}Baseline`);
      const packed = await deploy(`CursorBlocks${kind}Packed`);
      for (const scenario of kind.startsWith("Spec") ? ["exact", "range", "unbounded"] : ["exact"]) {
        const spec = scenario === "range" ? rangedSpec(Keys.Bytes, 16, 64, 0)
          : scenario === "unbounded" ? rangedSpec(Keys.Bytes, 0, 0, 0) : exactSpec(Keys.Bytes, 32);
        for (const count of [1, 32, 128]) {
          const input = concat(...Array(count).fill(block));
          const a = await baseline.measure(input, spec);
          const b = await packed.measure(input, spec);
          expect(b[1]).eq(a[1]);
          expect(b[1]).eq(BigInt(count * (kind.startsWith("Prefix") ? 16 : kind.startsWith("Enter") ? 32 : 40)));
          expect(b[2]).eq(a[2]);
          expect(b[2] >> 64n).eq(0xa5n);
          rows.push({ kind, scenario, count, baseline: Number(a[0]), packed: Number(b[0]), delta: Number(b[0] - a[0]) });
        }
      }
    }
    const slopes = rows.filter(r => r.count === 128).map(r => {
      const one = rows.find(s => s.kind === r.kind && s.scenario === r.scenario && s.count === 1);
      const middle = rows.find(s => s.kind === r.kind && s.scenario === r.scenario && s.count === 32);
      const baseline = (r.baseline - one.baseline) / 127;
      const packed = (r.packed - one.packed) / 127;
      expect((r.baseline - middle.baseline) / 96).eq(baseline);
      expect((r.packed - middle.packed) / 96).eq(packed);
      return { kind: r.kind, scenario: r.scenario, baseline, packed, deltaPerBlock: packed - baseline };
    });
    console.table(slopes);
    // No winner assertion: this is a comparison workbench for future candidates.
    mkdirSync(".npm-cache", { recursive: true });
    const compiler = hre.config.solidity.profiles.default.compilers[0];
    const viaIR = !!compiler.settings.viaIR;
    const configuration = { version: compiler.version, viaIR, evmVersion: compiler.settings.evmVersion,
      optimizer: compiler.settings.optimizer };
    writeFileSync(`.npm-cache/cursor-blocks-results${viaIR ? "-ir" : ""}.json`,
      JSON.stringify({ configuration, rows, slopes }, null, 2) + "\n");
  });
});
