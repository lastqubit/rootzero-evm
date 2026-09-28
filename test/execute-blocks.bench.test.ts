import { expect } from "chai";
import { deploy } from "./helpers/setup.js";
import { executeCases, executeStreams } from "./helpers/execute-blocks.js";
import { mkdirSync, writeFileSync } from "node:fs";

describe("Execute adapter optimization", function () {
  this.timeout(120_000);
  it("compares actual adapters against their frozen pre-migration bodies", async () => {
    const baseline = await deploy("ExecuteAdaptersBaseline");
    const current = await deploy("ExecuteAdaptersCurrent");
    const native = BigInt(await current.nativeAsset());
    const rows: any[] = [];
    for (const name of executeCases) {
      for (const count of [0, 1, 2, 4, 8, 16]) {
        for (const asset of (name === "Bootstrap" ? [native, 2n] : [native])) {
          const [state, input] = executeStreams(name, count, asset);
          for (const value of (name === "Bootstrap" ? [0, 100] : [100])) {
            const before = await baseline["measure" + name].staticCall(state, input, value);
            const after = await current["measure" + name].staticCall(state, input, value);
            expect(Array.from(after).slice(1), name).deep.eq(Array.from(before).slice(1));
            rows.push({ name, count, native: asset === native, value, before: Number(before.usedGas), after: Number(after.usedGas), delta: Number(after.usedGas - before.usedGas) });
          }
        }
      }
    }
    mkdirSync(".npm-cache", { recursive: true });
    writeFileSync(".npm-cache/execute-blocks-gas.json", JSON.stringify(rows, null, 2));
    console.table(rows.filter(r => r.count <= 4 && r.native && r.value === 100));
    for (const r of rows) {
      // Current shared cursor guards measure a fixed overhead in these adapters.
      // Bound it explicitly; other adapters must retain their migration savings.
      const allowance = r.name === "CreditAccount" || r.name === "Cashout"
        || (r.name === "Settle" && r.count === 0) ? 15 : 0;
      expect(r.delta, JSON.stringify(r)).lte(allowance);
    }
  });
});
