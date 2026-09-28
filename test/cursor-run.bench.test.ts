import { expect } from "chai";
import { mkdirSync, writeFileSync } from "node:fs";
import hre from "hardhat";
import { deploy } from "./helpers/setup.js";
import { concat, encodeBlock, Keys } from "./helpers/blocks.js";

describe("Cursor count-only run comparison", function () {
  this.timeout(120_000);
  it("compares Blocks, a fused scan, and shared primitives on complete and stopped runs", async () => {
    const rows: any[] = [];
    for (const variant of ["Baseline", "Composed", "Fused", "Current"]) {
      const helper = await deploy(`CursorRun${variant}`);
      const artifact = await hre.artifacts.readArtifact(`CursorRun${variant}`);
      for (const length of [0, 1, 33, 256]) for (const tail of ["empty", "different", "truncated"]) for (const count of [0, 1, 32, 128]) {
        const block = encodeBlock(Keys.Bytes, "0x" + "ab".repeat(length));
        const suffix = tail === "empty" ? "0x" : tail === "different" ? encodeBlock(Keys.String, "0x12") : concat(Keys.Bytes, "0xffffffff");
        const r = await helper.measure(concat(...Array(count).fill(block), suffix), Keys.Bytes);
        expect(r[1]).eq(BigInt(count));
        rows.push({ variant, length, tail, count, gas: Number(r[0]), runtimeBytes: (artifact.deployedBytecode.length - 2) / 2 });
      }
    }
    const slopes = rows.filter(r => r.count === 128).map(r => {
      const match = (s: any) => s.variant === r.variant && s.length === r.length && s.tail === r.tail;
      const one = rows.find(s => match(s) && s.count === 1), middle = rows.find(s => match(s) && s.count === 32);
      const perBlock = (r.gas - one.gas) / 127;
      expect((r.gas - middle.gas) / 96).eq(perBlock);
      return { variant: r.variant, length: r.length, tail: r.tail, perBlock, runtimeBytes: r.runtimeBytes };
    });
    console.table(slopes.filter(r => r.length === 33));
    mkdirSync(".npm-cache", { recursive: true });
    writeFileSync(".npm-cache/cursor-run-results.json", JSON.stringify({ compiler: hre.config.solidity.profiles.default.compilers[0], rows, slopes }, null, 2) + "\n");
  });
});
