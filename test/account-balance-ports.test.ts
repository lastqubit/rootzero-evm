import { expect } from "chai";
import { ethers } from "ethers";
import { deploy, getSigner } from "./helpers/setup.js";
import { concat, encodeAccountAmountBlock, encodeAccountAssetBlock, encodeUserAccount } from "./helpers/blocks.js";
import "./helpers/matchers.js";

describe("Unified account balance ports", () => {
  const asset = ethers.toBeHex(1n, 32);
  const user = encodeUserAccount("0x11");
  let host: Awaited<ReturnType<typeof deploy>>;
  let hostAccount: string;

  beforeEach(async () => {
    host = await deploy("TestAccountBalancePorts");
    const utils = await deploy("TestUtils");
    hostAccount = await utils.testHostNodeAccount(await host.host());
  });

  async function balances() {
    return host.getBalance(concat(encodeAccountAssetBlock(hostAccount, asset), encodeAccountAssetBlock(user, asset)));
  }

  it("credits, debits, and queries host and user accounts through the same endpoints", async () => {
    await host.portCreditAccount(concat(encodeAccountAmountBlock(hostAccount, asset, 100n), encodeAccountAmountBlock(user, asset, 40n)));
    await host.portDebitAccount(concat(encodeAccountAmountBlock(hostAccount, asset, 30n), encodeAccountAmountBlock(user, asset, 10n)));
    expect(await balances()).to.equal(concat(encodeAccountAmountBlock(hostAccount, asset, 70n), encodeAccountAmountBlock(user, asset, 30n)));
    for (const name of ["portCredit", "portDebit", "getAccountBalances"]) {
      expect(host.interface.getFunction(`${name}(bytes)`)).to.equal(null);
    }
  });

  it("rolls back earlier host debits when a later account has insufficient funds", async () => {
    await host.portCreditAccount(encodeAccountAmountBlock(hostAccount, asset, 100n));
    const before = await balances();
    await expect(host.portDebitAccount(concat(encodeAccountAmountBlock(hostAccount, asset, 30n), encodeAccountAmountBlock(user, asset, 1n))))
      .to.be.revertedWithCustomError(host, "InsufficientFunds");
    expect(await balances()).to.equal(before);
  });

  it("requires peer access to credit or debit the host account", async () => {
    const untrusted = host.connect(await getSigner(1)) as typeof host;
    const input = encodeAccountAmountBlock(hostAccount, asset, 1n);
    await expect(untrusted.portCreditAccount(input)).to.be.revertedWithCustomError(host, "AccessDenied");
    await expect(untrusted.portDebitAccount(input)).to.be.revertedWithCustomError(host, "AccessDenied");
  });
});
