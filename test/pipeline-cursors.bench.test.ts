import { expect } from "chai";
import { deploy } from "./helpers/setup.js";
import { concat, encodeStepBlock } from "./helpers/blocks.js";

describe("Independent Pipeline cursors", function () {
  this.timeout(120_000);
  it("compares independent input/stream cursors with the frozen packed-input pipeline", async () => {
    const packed = await deploy("TestPackedPipelineOptimization");
    const separate = await deploy("TestPipelineOptimization");
    const rows: object[] = [];
    for (const mode of ["internal", "external"] as const) {
      const method = mode === "internal" ? "localId" : "externalId";
      const oldId = await packed[method]();
      const newId = await separate[method]();
      for (const count of [0, 1, 2, 4, 8, 16]) {
        for (const input of ["0x", "0x123456"]) {
          const a = await packed.measure.staticCall(concat(...Array(count).fill(encodeStepBlock(oldId, 0n, input))), 123n, "0x");
          const b = await separate.measure.staticCall(concat(...Array(count).fill(encodeStepBlock(newId, 0n, input))), 123n, "0x");
          expect(a[1]).eq(b[1]);
          expect(b[0] <= a[0], mode + "/" + count + " gas regression").eq(true);
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
      expect(b[0] <= a[0], "handoff/" + count + " gas regression").eq(true);
      rows.push({ mode: "handoff", count, packed: Number(a[0]), separate: Number(b[0]), delta: Number(b[0] - a[0]) });
    }
    console.table(rows);
  });
});
