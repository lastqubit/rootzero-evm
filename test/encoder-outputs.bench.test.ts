import { expect } from "chai";
import { ethers } from "ethers";
import { mkdirSync, writeFileSync } from "node:fs";
import { deploy } from "./helpers/setup.js";
import { fixedLayouts } from "./helpers/encoder-outputs.js";

describe("Fixed Execution cursor writer gas", function () {
  this.timeout(120_000);
  it("measures allocation through finalization for short fixed-block streams", async () => {
    const helper = await deploy("TestEncoderOutputs"), rows: any[] = [];
    const fields = [1n, 2n, 3n, 4n, 5n].map(n => ethers.toBeHex(n, 32));
    for (const [kind, { name, words }] of fixedLayouts.entries()) for (const count of [1, 2, 4]) for (const grow of [false, true]) {
      const capacity = grow ? 0 : count * (8 + 32 * words);
      const before = await helper.fixedBlocks(kind, fields, count, capacity, true);
      const after = await helper.fixedBlocks(kind, fields, count, capacity, false);
      expect(after[1]).eq(before[1]);
      rows.push({ name, count, grow, before: Number(before[0]), after: Number(after[0]), saved: Number(before[0] - after[0]) });
    }
    console.table(rows.filter(r => r.count === 1 && !r.grow));
    mkdirSync(".npm-cache", { recursive: true });
    writeFileSync(".npm-cache/encoder-output-fixed-results.json", JSON.stringify(rows, null, 2));
  });
});
