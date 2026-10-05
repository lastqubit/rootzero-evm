import { expect } from "chai";
import { ethers } from "ethers";
import { deploy } from "./helpers/setup.js";
import "./helpers/matchers.js";

describe("Balance ledgers", () => {
  const asset = ethers.zeroPadValue("0x11", 32);
  const otherAsset = ethers.zeroPadValue("0x12", 32);
  const account = ethers.zeroPadValue("0x21", 32);
  const otherAccount = ethers.zeroPadValue("0x22", 32);

  it("has no legacy event ABI and leaves logging to callers", async () => {
    const ledger = await deploy("TestBalancesLedger");
    expect(ledger.interface.getEvent("EventAbi")).eq(null);
    expect(ledger.interface.getEvent("Balance")).eq(null);
    expect((await ledger.deploymentTransaction().wait()).logs).deep.eq([]);
    expect((await (await ledger.creditToAccount(account, asset, 10n)).wait()).logs).deep.eq([]);
    expect((await (await ledger.debitFromAccount(account, asset, 1n)).wait()).logs).deep.eq([]);
  });

  it("credits and debits account balances independently by account and asset", async () => {
    const ledger = await deploy("TestBalancesLedger");

    await ledger.creditToAccount(account, asset, 100n);
    await ledger.creditToAccount(account, otherAsset, 40n);
    await ledger.creditToAccount(otherAccount, asset, 25n);
    expect(await ledger.debitFromAccount.staticCall(account, asset, 30n)).to.equal(70n);
    await ledger.debitFromAccount(account, asset, 30n);

    expect(await ledger.accountBalance(account, asset)).to.equal(70n);
    expect(await ledger.accountBalance(account, otherAsset)).to.equal(40n);
    expect(await ledger.accountBalance(otherAccount, asset)).to.equal(25n);
  });

  it("rejects insufficient account balances", async () => {
    const ledger = await deploy("TestBalancesLedger");

    await expect(ledger.debitFromAccount(account, asset, 1n))
      .to.be.revertedWithCustomError(ledger, "InsufficientFunds");
  });
});
