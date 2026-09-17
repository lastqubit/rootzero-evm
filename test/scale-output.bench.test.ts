import { expect } from "chai";
import { deploy } from "./helpers/setup.js";

describe("Scaled output allocation benchmark", () => {
  it("compares scaled and original hints for larger and smaller output streams", async () => {
    const helper = await deploy("TestScaleOutput");
    const rows: object[] = [];
    for (const [capacity, numerator, denominator, count] of [[72, 32, 1, 32], [4608, 1, 2, 32]]) {
      const original = await helper.write(capacity, numerator, denominator, count, false);
      const scaled = await helper.write(capacity, numerator, denominator, count, true);
      expect(scaled[0]).to.equal(original[0]);
      expect(scaled[1] < original[1]).to.equal(true);
      rows.push({ capacity, numerator, denominator, originalGas: Number(original[2]), scaledGas: Number(scaled[2]),
        originalMemory: Number(original[1]), scaledMemory: Number(scaled[1]) });
    }
    console.table(rows);
  });
});
