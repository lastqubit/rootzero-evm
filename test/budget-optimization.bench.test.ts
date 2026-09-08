import { expect } from "chai";
import { ethers } from "ethers";
import { mkdirSync, writeFileSync } from "node:fs";
import { deploy } from "./helpers/setup.js";

async function outcome(call: () => Promise<any>) {
  try { const r = await call(); return { remaining: r.remaining, consumed: r.consumed }; }
  catch (error: any) {
    const data = error.data ?? error.info?.error?.data;
    if (typeof data !== "string") throw error;
    return { error: data };
  }
}
describe("Budget subtraction optimization", () => {
  it("benchmarks scalar, memory, and resource-lane budget deductions", async () => {
    const helper = await deploy("TestBudgetOptimization");
    const rows: object[] = [];
    for (const mode of [0, 1, 2, 3]) {
      const before = await helper.measure(false, mode, 100, 11);
      const after = await helper.measure(true, mode, 100, 11);
      expect(after.remaining).to.equal(89n);
      expect(after.consumed).to.equal(11n);
      expect(after.usedGas).to.be.lessThan(before.usedGas);
      rows.push({ mode, before: Number(before.usedGas), after: Number(after.usedGas), saved: Number(before.usedGas - after.usedGas) });
    }
    mkdirSync(".npm-cache", { recursive: true });
    writeFileSync(".npm-cache/budget-results.json", JSON.stringify(rows, null, 2) + "\n");
    console.table(rows);
  });
  it("preserves insufficient-value errors and consumes only the low resource lane", async () => {
    const helper = await deploy("TestBudgetOptimization");
    for (const mode of [0, 1, 2, 3]) {
      for (const amount of [0n, 1n, 100n, (1n << 128n) - 1n, ethers.MaxUint256]) {
        for (const value of [0n, 1n, 100n, (1n << 128n) - 1n, 1n << 128n, (7n << 128n) | 11n, ethers.MaxUint256]) {
          const debit = mode < 2 ? value : value & ((1n << 128n) - 1n);
          const expected = debit > amount ? { error: ethers.id("InsufficientValue()").slice(0, 10) }
            : { remaining: amount - debit, consumed: debit };
          expect(await outcome(() => helper.measure(false, mode, amount, value))).to.deep.equal(expected);
          expect(await outcome(() => helper.measure(true, mode, amount, value))).to.deep.equal(expected);
        }
      }
    }
  });
});
