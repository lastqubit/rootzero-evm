import { expect } from "chai";
import { ethers } from "ethers";
import { mkdirSync, writeFileSync } from "node:fs";
import hre from "hardhat";
import { deploy } from "./helpers/setup.js";
import { concat, encodePositionConstraintsBlock } from "./helpers/blocks.js";

describe("Cursor position-constraint structure comparison", function () {
  this.timeout(120_000);
  it("compares readable, grouped, fused and struct-decoding paths", async () => {
    const rows: any[] = [], attempts: any[] = [];
    const asset = ethers.toBeHex(1, 32), liability = ethers.toBeHex(2, 32), other = ethers.toBeHex(3, 32), max = ethers.MaxUint256;
    const baseline = await deploy("CursorExpectBaseline");
    for (const variant of ["Baseline", "Readable", "Packed", "Grouped", "Fused", "Decoded", "ReadCompare", "Current"]) {
      const helper = await deploy(`CursorExpect${variant}`), artifact = await hre.artifacts.readArtifact(`CursorExpect${variant}`);
      const runtimeBytes = (artifact.deployedBytecode.length - 2) / 2;
      for (const [scenario, minimum, maximum, amount, debt] of [
        ["equal", 123n, 456n, 123n, 456n], ["better", 123n, 456n, 124n, 455n],
        ["zero", 0n, 0n, 0n, 0n], ["full", max, max, max, max],
      ] as const) {
        const block = encodePositionConstraintsBlock(asset, minimum, liability, maximum), position = [asset, amount, liability, debt, other];
        for (const method of ["measure", "measureDiscard"]) for (const count of [1, 32, 128]) {
          const source = concat(...Array(count).fill(block)), a = await baseline[method](source, position), b = await helper[method](source, position);
          expect(b[1]).eq(BigInt(count)); expect(b[1]).eq(a[1]); expect(b[2]).eq(a[2]); expect(b[2] >> 64n).eq(0xa5n);
          rows.push({ variant, scenario, method, count, gas: Number(b[0]), runtimeBytes });
        }
      }
      const block = encodePositionConstraintsBlock(asset, 123n, liability, 456n);
      for (const [scenario, position, error] of [
        ["asset", [other, 123, liability, 456, other], "UnexpectedValue()"],
        ["liability", [asset, 123, other, 456, other], "UnexpectedValue()"],
        ["assetAmount", [asset, 122, liability, 456, other], "OutOfRange()"],
        ["debt", [asset, 123, liability, 457, other], "OutOfRange()"],
      ] as const) {
        const r = await helper.measureAttempt(block, position);
        expect(r[1]).eq(false); expect(r[2]).eq(ethers.id(error).slice(0, 10));
        attempts.push({ variant, scenario, gas: Number(r[0]) });
      }
    }
    const slopes = rows.filter(r => r.count === 128).map(r => {
      const match = (s: any) => s.variant === r.variant && s.scenario === r.scenario && s.method === r.method;
      const one = rows.find(s => match(s) && s.count === 1), middle = rows.find(s => match(s) && s.count === 32);
      const perBlock = (r.gas - one.gas) / 127;
      // Allocating a constraints struct grows memory in the Decoded candidate.
      if (r.variant !== "Decoded") expect((r.gas - middle.gas) / 96).eq(perBlock);
      return { variant: r.variant, scenario: r.scenario, method: r.method, perBlock, runtimeBytes: r.runtimeBytes };
    });
    if (hre.config.solidity.profiles.default.compilers[0].settings.viaIR) {
      for (const row of slopes.filter(r => r.variant === "Current")) {
        const previous = slopes.find(r => r.variant === "ReadCompare" && r.scenario === row.scenario && r.method === row.method);
        expect(row.perBlock).at.most(previous!.perBlock);
      }
    }
    console.table(slopes.filter(r => r.scenario === "equal")); console.table(attempts);
    mkdirSync(".npm-cache", { recursive: true });
    writeFileSync(".npm-cache/cursor-expect-results.json", JSON.stringify({ compiler: hre.config.solidity.profiles.default.compilers[0], rows, slopes, attempts }, null, 2) + "\n");
  });
});
