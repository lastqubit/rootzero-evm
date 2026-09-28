import { expect } from "chai";
import { ethers } from "ethers";
import { writeFileSync } from "node:fs";
import hre from "hardhat";
import { deploy } from "./helpers/setup.js";
import { concat, encodeBlock, encodePositionConstraintsBlock, Keys } from "./helpers/blocks.js";

describe("Deferred validated constraint cursors", function () {
  this.timeout(120000);
  const word = (v: bigint) => ethers.toBeHex(v, 32);
  it("measures value-only validation and sharing its implementation", async () => {
    const rows: any[] = [];
    for (const variant of ["Current", "Values"]) {
      const name = `CursorDeferredConstraint${variant}`, helper = await deploy(name);
      const artifact = await hre.artifacts.readArtifact(name);
      for (const [scenario, min, max, amount, debt] of [
        ["equal", 7n, 3n, 7n, 3n], ["better", 7n, 3n, 8n, 2n],
        ["zero", 0n, 0n, 0n, 0n], ["full", ethers.MaxUint256, ethers.MaxUint256, ethers.MaxUint256, ethers.MaxUint256],
      ] as const) for (const includeSetup of [false, true]) for (const count of [1, 32, 128]) {
        const block = encodePositionConstraintsBlock(word(1n), min, word(2n), max);
        const source = concat(...Array(count).fill(concat("0xff", block)));
        const offsets = Array.from({ length: count }, (_, i) => i * 137 + 1);
        const r = await helper.measure(source, offsets, Array(count).fill(136), [word(1n), amount, word(2n), debt, word(99n)], includeSetup);
        expect(r[1]).eq(BigInt(count));
        rows.push({ variant, scenario, includeSetup, count, gas: Number(r[0]), bytes: (artifact.deployedBytecode.length - 2) / 2 });
      }
      const block = encodePositionConstraintsBlock(word(1n), 7n, word(2n), 3n);
      const good = [word(1n), 7n, word(2n), 3n, word(99n)];
      for (const [source, length, position, reason] of [
        [block, 135, good, "OutOfBounds()"],
        [encodeBlock(Keys.Bytes, "0x" + "00".repeat(128)), 136, good, "InvalidBlock()"],
        [block, 136, [word(3n), 0n, word(2n), ethers.MaxUint256, word(0n)], "UnexpectedValue()"],
        [block, 136, [word(1n), 7n, word(3n), 3n, word(0n)], "UnexpectedValue()"],
        [block, 136, [word(1n), 6n, word(2n), 3n, word(0n)], "OutOfRange()"],
        [block, 136, [word(1n), 7n, word(2n), 4n, word(0n)], "OutOfRange()"],
      ] as const) {
        let error: unknown;
        try { await helper.measure(source, [0], [length], position, false); }
        catch (e: any) { error = e.data ?? e.info?.error?.data; }
        expect(error).eq(ethers.id(reason).slice(0, 10));
      }
    }
    const summary = rows.filter(r => r.scenario === "equal" && r.count === 128).map(r => {
      const one = rows.find(x => x.variant === r.variant && x.scenario === r.scenario && x.includeSetup === r.includeSetup && x.count === 1);
      const middle = rows.find(x => x.variant === r.variant && x.scenario === r.scenario && x.includeSetup === r.includeSetup && x.count === 32);
      const slope = (r.gas - one.gas) / 127;
      // Setup allocates an array: memory expansion need not be linear.
      if (!r.includeSetup) expect((r.gas - middle.gas) / 96).eq(slope);
      return { variant: r.variant, setup: r.includeSetup, gas1: one.gas, gas32: middle.gas, gas128: r.gas,
        perCheck: r.includeSetup ? null : slope, bytes: r.bytes };
    });
    console.table(summary);
    writeFileSync(".npm-cache/cursor-deferred-constraints-results.json", JSON.stringify({ compiler: hre.config.solidity.profiles.default.compilers[0], rows, summary }, null, 2));
  });
});
