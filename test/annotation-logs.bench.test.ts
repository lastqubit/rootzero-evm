import { expect } from "chai";
import { deploy } from "./helpers/setup.js";

describe("Annotation logging gas", () => {
  it("compares the legacy ABI envelope with the block envelope", async () => {
    const before = await deploy("PreviousAnnotationLog");
    const after = await deploy("TestAnnotationLogs");
    const rows: Record<string, number>[] = [];
    for (const length of [0, 1, 32, 64, 128, 512]) {
      const data = "0x" + "ab".repeat(length);
      const oldGas = await before.measure.staticCall(123n, data);
      const newGas = await after.measure.staticCall(123n, data);
      expect(newGas < oldGas).eq(true);
      rows.push({ length, before: Number(oldGas), after: Number(newGas), saved: Number(oldGas - newGas) });
    }
    console.table(rows);
  });
});
