import { expect } from "chai";
import { deploy } from "./helpers/setup.js";
import { executeStreams } from "./helpers/execute-blocks.js";
import { mkdirSync, writeFileSync } from "node:fs";

describe("Execute output preallocation", function () {
  this.timeout(120_000);
  it("compares reserved, unchecked cursor, and exact output allocation", async () => {
    const baseline = await deploy("ExecuteOutputBaseline");
    const candidates = await Promise.all(["Reserved", "Unchecked", "Exact", "Current"].map(async name => ({ name, helper: await deploy("ExecuteOutput" + name) })));
    const native = BigInt(await baseline.nativeAsset());
    const rows: any[] = [];
    for (const allocate of [false, true]) {
      await baseline.setAllocate(allocate);
      for (const { helper } of candidates) await helper.setAllocate(allocate);
      for (const command of ["Bootstrap", "DebitAccount"]) {
        for (const count of [0, 1, 2, 4, 8, 16]) {
          for (const asset of (command === "Bootstrap" ? [native, 2n] : [2n])) {
            for (const value of (command === "Bootstrap" ? [0, 100] : [100])) {
              const [state, input] = executeStreams(command, count, asset);
              const before = await baseline["measure" + command].staticCall(state, input, value);
              for (const { name, helper } of candidates) {
                if (command === "Bootstrap" && name === "Current") continue;
                const after = await helper["measure" + command].staticCall(state, input, value);
                expect(Array.from(after).slice(2), command + "/" + name).deep.eq(Array.from(before).slice(2));
                rows.push({ command, variant: name, count, native: asset === native, value, allocate,
                  before: Number(before.usedGas), after: Number(after.usedGas), saved: Number(before.usedGas - after.usedGas),
                  allocationSaved: Number(before.allocated - after.allocated) });
              }
            }
          }
        }
      }
    }
    mkdirSync(".npm-cache", { recursive: true });
    writeFileSync(".npm-cache/execute-output-preallocation.json", JSON.stringify(rows, null, 2));
    console.table(rows.filter(r => r.count <= 4 && !r.allocate && r.value === 100 && (r.command === "DebitAccount" || r.native)));
    for (const row of rows.filter(r => r.variant === "Exact" || r.variant === "Current")) expect(row.saved, JSON.stringify(row)).gte(0);
  });
});
