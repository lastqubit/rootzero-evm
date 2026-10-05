import { expect } from "chai";
import { deploy } from "./helpers/setup.js";
import { concat, encodeStepBlock } from "./helpers/blocks.js";

describe("Independent Pipeline cursors", function () {
  this.timeout(120_000);
  it("compares independent input/stream cursors with the frozen packed-input pipeline and matching context logs", async () => {
    const packed = await deploy("TestPackedPipelineOptimization");
    const separate = await deploy("TestPipelineOptimization");
    const rows: { mode: string; count: number; bytes?: number; packed: number; separate: number; delta: number }[] = [];
    for (const mode of ["internal", "external"] as const) {
      const method = mode === "internal" ? "localId" : "externalId";
      const oldId = await packed[method]();
      const newId = await separate[method]();
      for (const count of [0, 1, 2, 4, 8, 16]) {
        for (const input of ["0x", "0x123456"]) {
          const a = await packed.measure.staticCall(concat(...Array(count).fill(encodeStepBlock(oldId, 0n, input))), 123n, "0x");
          const b = await separate.measure.staticCall(concat(...Array(count).fill(encodeStepBlock(newId, 0n, input))), 123n, "0x");
          expect(a[1]).eq(b[1]);
          rows.push({ mode, count, bytes: (input.length - 2) / 2,
            packed: Number(a[0]), separate: Number(b[0]), delta: Number(b[0] - a[0]) });
        }
      }
    }
    const oldHandoff = (await packed.externalId()) | (128n << 224n);
    const newHandoff = (await separate.externalId()) | (128n << 224n);
    await (await packed.allow(oldHandoff)).wait();
    await (await separate.allow(newHandoff)).wait();
    for (const count of [0, 1, 4]) {
      const oldSteps = concat(encodeStepBlock(oldHandoff, 0n, "0x123456"),
        ...Array(count).fill(encodeStepBlock(await packed.localId(), 0n, "0x")));
      const newSteps = concat(encodeStepBlock(newHandoff, 0n, "0x123456"),
        ...Array(count).fill(encodeStepBlock(await separate.localId(), 0n, "0x")));
      const a = await packed.measure.staticCall(oldSteps, 0n, "0x");
      const b = await separate.measure.staticCall(newSteps, 0n, "0x");
      expect(a[1]).eq(b[1]);
      rows.push({ mode: "handoff", count, packed: Number(a[0]), separate: Number(b[0]), delta: Number(b[0] - a[0]) });
    }
    console.table(rows);
    for (const row of rows) {
      // Solidity 0.8.35/viaIR: checked budget addition and the centralized invocation
      // trade a small measured cost for simpler code versus the frozen assembly baseline.
      // Matching PIPELINE logs add a fixed 9-gas compiler-layout difference.
      // Keep an explicit ceiling so further regressions still fail this benchmark.
      const ceiling = row.mode === "handoff" ? 48
        : (row.mode === "internal" ? 29 : 39) * row.count + 1;
      expect(row.delta, row.mode + "/" + row.count + " gas regression").at.most(ceiling);
    }
  });
});
