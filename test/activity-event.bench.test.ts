import { expect } from "chai";
import { ethers } from "ethers";
import { deploy } from "./helpers/setup.js";

describe("Activity event gas", () => {
  it("measures the added subject field for empty, single, and mixed codes", async () => {
    const previous = await deploy("PreviousActivityEventGas");
    const current = await deploy("TestActivityEventGas");
    const account = ethers.toBeHex(1, 32);
    const rows: object[] = [];
    for (const [action, effect] of [[0n, 0n], [80n, 0n], [0n, 0x80000002n], [80n, 0x80000000n]]) {
      const codes = action === 0n ? effect : action | (effect << 32n);
      const before = await previous.measure.staticCall(account, ethers.toBeHex(2, 32), codes, 0);
      const after = await current.measure.staticCall(account, ethers.toBeHex(2, 32), codes, 0);
      expect(after).to.be.greaterThan(before);
      rows.push({ action: action.toString(), effect: effect.toString(),
        before: Number(before), after: Number(after), added: Number(after - before) });
    }
    console.table(rows);
  });
});
