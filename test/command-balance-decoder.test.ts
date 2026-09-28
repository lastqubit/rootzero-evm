import { expect } from "chai";
import { ethers } from "ethers";
import { deploy } from "./helpers/setup.js";
import { concat, encodeBalanceBlock, encodeBalanceConstraintsBlock, encodeContextBlock, encodeBlock, Keys } from "./helpers/blocks.js";
import "./helpers/matchers.js";

describe("Production command cursor balance decoding", function () {
  const account = ethers.toBeHex(3n, 32), asset = ethers.toBeHex(1n, 32);
  const balance = encodeBalanceBlock(asset, 100n);
  const constraints = encodeBalanceConstraintsBlock(asset, 90n, 110n);
  let host: any;
  before(async () => { host = await deploy("CommandBalanceCurrent"); });
  it("advances both sources through paired commands and preserves full-width balances", async () => {
    for (const amount of [0n, 100n, ethers.MaxUint256]) {
      const state = concat(encodeBalanceBlock(asset, amount), balance);
      const input = concat(encodeBalanceConstraintsBlock(asset, amount, amount), constraints);
      expect(Array.from(await host.checkBalance.staticCall(encodeContextBlock(account, state, input)))).deep.eq([state, 0n]);
    }
  });
  it("checks the balance header before bounds without accepting truncated state", async () => {
    for (const state of ["0x", "0x00", encodeBlock(Keys.Bytes, "0x")]) {
      await expect(host.checkBalance(encodeContextBlock(account, state, constraints)))
        .to.be.revertedWithCustomError(host, "InvalidBlock");
    }
    for (const size of [8, 9, 40, 71]) {
      // Physical input follows state; containment must prevent reading into it.
      await expect(host.checkBalance(encodeContextBlock(account, ethers.dataSlice(balance, 0, size), constraints)))
        .to.be.revertedWithCustomError(host, "OutOfBounds");
    }
  });
  it("rolls back the withdrawal hook when a later balance is malformed", async () => {
    const state = concat(balance, encodeBlock(Keys.Bytes, "0x"));
    await expect(host.withdraw(encodeContextBlock(account, state, "0x")))
      .to.be.revertedWithCustomError(host, "InvalidBlock");
    expect(await host.delivered(account, asset)).eq(0n);
  });
});
