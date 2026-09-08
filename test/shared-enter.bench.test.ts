import { expect } from "chai";
import { ethers } from "ethers";
import { mkdirSync, writeFileSync } from "node:fs";
import { deploy } from "./helpers/setup.js";
import { concat, encodeBlock, exactSpec, Keys } from "./helpers/blocks.js";

const spec = exactSpec(Keys.Bytes, 208);
const parent = encodeBlock(Keys.Bytes, "0x" + "11".repeat(208));
async function outcome(call: () => Promise<any>) {
  try { return Array.from(await call()); }
  catch (error: any) {
    const data = error.data ?? error.info?.error?.data;
    if (typeof data !== "string") throw error;
    return { error: data };
  }
}

describe("Shared versus direct enter validation", function () {
  this.timeout(120_000);
  it("benchmarks all overloads with returned bounds used and discarded", async () => {
    const rows: any[] = [];
    for (const kind of ["Execution", "Decoder"]) {
      const current = await deploy(`Test${kind}PreviousEnter`);
      const shared = await deploy(kind === "Execution" ? "TestEnterCurrent" : "TestDecoderEnterCurrent");
      const direct = await deploy(`Test${kind}DirectEnter`);
      for (const mode of [0, 1, 2, 3]) {
        for (const method of ["measure", "measureDiscard"]) {
          for (const count of [1, 32]) {
            const input = concat(...Array(count).fill(parent));
            const a = await current[method](input, spec, 104, mode);
            const b = await shared[method](input, spec, 104, mode);
            const c = await direct[method](input, spec, 104, mode);
            expect(b[1]).to.equal(a[1]);
            expect(a[0] - b[0]).to.equal(BigInt((mode % 2 === 0 ? 78 : 0) * count));
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

  it("preserves returned bounds, metadata, and exact malformed-input errors", async () => {
    for (const kind of ["Execution", "Decoder"]) {
      const current = await deploy(`Test${kind}PreviousEnter`);
      const shared = await deploy(kind === "Execution" ? "TestEnterCurrent" : "TestDecoderEnterCurrent");
      const direct = await deploy(`Test${kind}DirectEnter`);
      for (const mode of [0, 1, 2, 3]) {
        for (const input of [parent, "0x", ethers.dataSlice(parent, 0, 7), ethers.dataSlice(parent, 0, 8),
          ethers.dataSlice(parent, 0, 112), encodeBlock(Keys.Bytes, "0x")]) {
          for (const expected of [spec, exactSpec(Keys.String, 208), exactSpec(Keys.Bytes, 207),
            spec & ~(0xffffffffn << 160n)]) {
            for (const amount of [0n, 104n, 208n, 209n, ethers.MaxUint256]) {
              const args = [input, expected, amount, mode];
              const before = await outcome(() => current.enterOnce(...args));
              expect(await outcome(() => shared.enterOnce(...args))).to.deep.equal(before);
              expect(await outcome(() => direct.enterOnce(...args))).to.deep.equal(before);
            }
          }
        }
      }
    }
  });
});
