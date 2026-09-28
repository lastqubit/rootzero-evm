import { expect } from "chai";
import { ethers } from "ethers";
import { deploy } from "./helpers/setup.js";
import { block, executeStreams } from "./helpers/execute-blocks.js";
import { Keys } from "./helpers/blocks.js";

async function failure(call: Promise<unknown>) {
  try { await call; } catch (error: any) { return error.data ?? error.info?.error?.data; }
  throw new Error("Expected revert");
}

describe("Execute output preallocation behavior", () => {
  it("preserves errors and their order before output can be exposed", async () => {
    const baseline = await deploy("ExecuteOutputBaseline");
    const candidates = await Promise.all(["Reserved", "Unchecked", "Exact", "Current"].map(name => deploy("ExecuteOutput" + name)));
    const native = BigInt(await baseline.nativeAsset());
    for (const command of ["Bootstrap", "DebitAccount"]) {
      const [, input] = executeStreams(command, 2, native);
      const key = command === "Bootstrap" ? Keys.Bootstrap : Keys.Amount;
      const hookFailure = command === "Bootstrap" ? block(key, [2n, ethers.MaxUint256, 0n]) : block(key, [2n, ethers.MaxUint256]);
      const overflow = block(Keys.Bootstrap, [native, ethers.MaxUint256, 1n]);
      const cases = [["0x01", input, 100], ["0x", input + "01", 100],
        ["0x", ethers.concat(["0xffffffff", ethers.dataSlice(input, 4)]), 100],
        ["0x", hookFailure, 0], ["0x", hookFailure + "01", 0]];
      if (command === "Bootstrap") cases.push(["0x", overflow, 0]);
      for (const args of cases) {
        const expected = await failure(baseline["measure" + command].staticCall(...args));
        for (const helper of candidates) {
          expect(await failure(helper["measure" + command].staticCall(...args))).eq(expected);
          expect(await helper.checksum()).eq(0n);
        }
      }
    }
  });

  it("preserves full-width amounts and unaligned final output across hook allocations", async () => {
    const baseline = await deploy("ExecuteOutputBaseline");
    const candidates = await Promise.all(["Reserved", "Unchecked", "Exact", "Current"].map(name => deploy("ExecuteOutput" + name)));
    for (const helper of [baseline, ...candidates]) await helper.setAllocate(true);
    for (const command of ["Bootstrap", "DebitAccount"]) {
      const amount = (1n << 255n) + 123n;
      const input = command === "Bootstrap" ? block(Keys.Bootstrap, [2n, amount, 0n]) : block(Keys.Amount, [2n, amount]);
      const expected = await baseline["measure" + command].staticCall("0x", input, 0);
      expect(expected.output).eq(block(Keys.Balance, [2n, amount]));
      for (const helper of candidates) {
        const result = await helper["measure" + command].staticCall("0x", input, 0);
        expect(Array.from(result).slice(2)).deep.eq(Array.from(expected).slice(2));
      }
    }
  });
});
