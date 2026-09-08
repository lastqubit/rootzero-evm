import { expect } from "chai";
import { ethers } from "ethers";
import { mkdirSync, writeFileSync } from "node:fs";
import { deploy } from "./helpers/setup.js";
import { encodeBlock, Keys } from "./helpers/blocks.js";

describe("Factory length validation benchmark", function () {
  this.timeout(120_000);
  it("compares factory and standalone writer gas with identical bytes", async () => {
    const helper = await deploy("TestFactoryValidation");
    const rows: object[] = [];
    for (const kind of [0, 1, 2, 3, 4, 5, 6]) {
      for (const size of [0, 1, 31, 32, 33, 256, 4096]) {
        const input = "0x" + "ab".repeat(size);
        const key = kind == 2 ? Keys.List : kind == 4 ? Keys.String : Keys.Bytes;
        const before = await helper.measure(false, kind, input);
        const after = await helper.measure(true, kind, input);
        expect(before.output).to.equal(encodeBlock(key, input));
        expect(after.output).to.equal(before.output);
        if (kind < 5) expect(after.usedGas).to.be.lessThan(before.usedGas);
        // Identical standalone bodies can differ slightly because of harness
        // branch routing; reject an extra helper call's larger overhead.
        else expect(after.usedGas).to.be.at.most(before.usedGas + 12n);
        rows.push({ kind, size, before: Number(before.usedGas), after: Number(after.usedGas),
          saved: Number(before.usedGas - after.usedGas) });
      }
    }
    mkdirSync(".npm-cache", { recursive: true });
    writeFileSync(".npm-cache/factory-validation-results.json", JSON.stringify(rows, null, 2) + "\n");
    console.table(rows.filter((r: any) => [0, 4096].includes(r.size)));
  });

  it("retains ValueOverflow for oversized factory inputs and direct writers", async () => {
    const helper = await deploy("TestFactoryValidation");
    const expected = ethers.id("ValueOverflow()").slice(0, 10);
    for (const optimized of [false, true]) {
      for (const kind of [0, 1, 2, 3, 4, 5, 6]) {
        for (const length of [1n << 32n, ethers.MaxUint256]) {
          let failure: string | undefined;
          try {
            await helper.oversized(optimized, kind, "0x", length);
          } catch (error: any) {
            failure = error.data ?? error.info?.error?.data;
          }
          expect(failure).to.equal(expected);
        }
      }
    }
  });
});
