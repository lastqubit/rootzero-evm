import { expect } from "chai";
import { mkdirSync, writeFileSync } from "node:fs";
import { deploy } from "./helpers/setup.js";
import { concat, encodeBlock, exactSpec, Keys } from "./helpers/blocks.js";

const spec = exactSpec(Keys.Bytes, 208);
const parent = encodeBlock(Keys.Bytes, "0x" + "11".repeat(208));

describe("Shared versus direct enter validation", function () {
  this.timeout(120_000);
  it("benchmarks all overloads with returned bounds used and discarded", async () => {
    const rows: any[] = [];
    for (const kind of ["Execution"]) {
      const current = await deploy(`Test${kind}PreviousEnter`);
      const shared = await deploy("TestEnterCurrent");
      const direct = await deploy(`Test${kind}DirectEnter`);
      for (const mode of [0, 1, 2, 3]) {
        for (const method of ["measure", "measureDiscard"]) {
          for (const count of [1, 32]) {
            const input = concat(...Array(count).fill(parent));
            const a = await current[method](input, spec, 104, mode);
            const b = await shared[method](input, spec, 104, mode);
            const c = await direct[method](input, spec, 104, mode);
            expect(b[1]).to.equal(a[1]);
            expect(c[1]).to.equal(a[1]);
            if (method === "measure") expect(a[1]).to.equal(BigInt(count * 208));
            rows.push({ kind, mode, method, count, current: Number(a[0]), shared: Number(b[0]), direct: Number(c[0]),
              sharedSaved: Number(a[0] - b[0]), directSaved: Number(a[0] - c[0]) });
          }
        }
      }
    }
    console.table(rows.filter(r => r.count === 32));
    mkdirSync(".npm-cache", { recursive: true });
    writeFileSync(".npm-cache/shared-enter-results.json", JSON.stringify(rows, null, 2) + "\n");
  });
});
