import { expect } from "chai";
import { ethers } from "ethers";
import { deploy } from "./helpers/setup.js";
import { encodeUserAccount } from "./helpers/blocks.js";
import "./helpers/matchers.js";

describe("Settlement ledger", () => {
  const account = encodeUserAccount("0x11");
  const counterparty = encodeUserAccount("0x22");
  const asset = ethers.toBeHex(1n, 32);
  const liability = ethers.toBeHex(2n, 32);
  let ledger: Awaited<ReturnType<typeof deploy>>;

  beforeEach(async () => {
    ledger = await deploy("TestSettlement");
    await ledger.seed(account, liability, 40n);
    await ledger.seed(counterparty, asset, 100n);
  });

  async function balances() {
    return Promise.all([
      ledger.balance(account, asset), ledger.balance(account, liability),
      ledger.balance(counterparty, asset), ledger.balance(counterparty, liability),
    ]);
  }

  it("enforces inclusive limits before changing balances", async () => {
    const position = [asset, 100n, liability, 40n, counterparty];
    for (const limits of [[101n, 40n], [100n, 39n]]) {
      const before = await balances();
      await expect(ledger.applyLimitedPosition(account, position, limits))
        .to.be.revertedWithCustomError(ledger, "AmountOutOfRange");
      expect(await balances()).to.deep.equal(before);
    }
    await ledger.applyLimitedPosition(account, position, [100n, 40n]);
    expect(await balances()).to.deep.equal([100n, 0n, 0n, 40n]);
  });

  it("exchanges both sides exactly", async () => {
    await ledger.applyPosition(account, [asset, 100n, liability, 40n, counterparty]);
    expect(await balances()).to.deep.equal([100n, 0n, 0n, 40n]);
  });

  it("settles a deterministic host account while rejecting the corresponding host node", async () => {
    const utils = await deploy("TestUtils");
    const address = await ledger.getAddress();
    const hostAccount = await utils.testToHostAccount(address);
    await ledger.seed(hostAccount, asset, 100n);
    await ledger.applyPosition(account, [asset, 100n, liability, 40n, hostAccount]);
    expect(await ledger.balance(hostAccount, asset)).to.equal(0n);
    expect(await ledger.balance(hostAccount, liability)).to.equal(40n);
    expect(await ledger.balance(account, asset)).to.equal(100n);
    expect(await ledger.balance(account, liability)).to.equal(0n);
    const node = ethers.toBeHex((0x03020200n << 224n) | BigInt(address), 32);
    await expect(ledger.applyPosition(account, [asset, 0n, liability, 0n, node]))
      .to.be.revertedWithCustomError(ledger, "InvalidAccount");
  });

  for (const [amount, debt] of [[100n, 40n], [0n, 0n]]) {
    it(`rejects zero counterparty (${amount}, ${debt}) without changing balances`, async () => {
      const before = await balances();
      await expect(ledger.applyPosition(account, [asset, amount, liability, debt, ethers.ZeroHash]))
        .to.be.revertedWithCustomError(ledger, "InvalidAccount");
      expect(await balances()).to.deep.equal(before);
    });
  }

  for (const [amount, debt] of [[101n, 40n], [100n, 41n]]) {
    it(`rolls back both sides when funds are insufficient (${amount}, ${debt})`, async () => {
      const before = await balances();
      await expect(ledger.applyPosition(account, [asset, amount, liability, debt, counterparty]))
        .to.be.revertedWithCustomError(ledger, "InsufficientFunds");
      expect(await balances()).to.deep.equal(before);
    });
  }

  it("settles liability-only and asset-only positions", async () => {
    await ledger.applyPosition(account, [ethers.ZeroHash, 0n, liability, 40n, counterparty]);
    expect(await balances()).to.deep.equal([0n, 0n, 100n, 40n]);
    await ledger.applyPosition(account, [asset, 100n, ethers.ZeroHash, 0n, counterparty]);
    expect(await balances()).to.deep.equal([100n, 0n, 0n, 40n]);
  });

  it("handles the same asset on both sides with liability settled first", async () => {
    await ledger.applyPosition(account, [liability, 30n, liability, 40n, counterparty]);
    expect(await balances()).to.deep.equal([0n, 30n, 100n, 10n]);
  });

  it("preserves balances when the account is its own counterparty", async () => {
    const before = await balances();
    await ledger.applyPosition(account, [liability, 30n, liability, 40n, account]);
    expect(await balances()).to.deep.equal(before);
  });

  it("rejects non-account counterparties even when both amounts are zero", async () => {
    await expect(ledger.applyPosition(account, [asset, 0n, liability, 0n, asset]))
      .to.be.revertedWithCustomError(ledger, "InvalidAccount");
  });
});
