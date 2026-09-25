import { expect } from "chai";
import { deploy } from "./helpers/setup.js";
import { concat, encodeStepBlock } from "./helpers/blocks.js";

describe("Pipeline parser and credit gas", function () {
  this.timeout(120_000);
  it("measures internal and external steps with identical command work", async () => {
    const host = await deploy("TestPipelineOptimization");
    const rows: { mode: string; count: number; gas: number }[] = [];
    for (const [mode, id] of [["internal", await host.localId()], ["external", await host.externalId()]] as const) {
      for (const count of [0, 1, 2, 4, 8, 16]) {
        const steps = concat(...Array(count).fill(encodeStepBlock(id, 0n, "0x")));
        const [gas, remaining] = await host.measure.staticCall(steps, 123n, "0x");
        expect(remaining).to.equal(123n);
        rows.push({ mode, count, gas: Number(gas) });
      }
    }
    console.table(rows);
  });
});
