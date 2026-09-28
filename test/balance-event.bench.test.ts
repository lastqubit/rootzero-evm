import { expect } from "chai";
import { ethers } from "ethers";
import { deploy } from "./helpers/setup.js";

describe("Balance event gas", function () {
  it("measures the emission with identical inputs before and after removing change", async () => {
    const previous = await deploy("PreviousBalanceEventGas");
    const current = await deploy("TestBalanceEventGas");
    const account = ethers.toBeHex(1, 32);
    const asset = ethers.toBeHex(2, 32);
    const rows: object[] = [];
    for (const balance of [0n, 70n, ethers.MaxUint256]) {
      for (const change of [-30n, 0n, 30n]) {
        const before = await previous.measure.staticCall(account, asset, balance, change);
        const after = await current.measure.staticCall(account, asset, balance, change);
        expect(after).to.be.lessThan(before);
        rows.push({ balance: balance.toString(), change: change.toString(),
          before: Number(before), after: Number(after), saved: Number(before - after) });
      }
    }
    console.table(rows);
  });
});
