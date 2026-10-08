import { expect } from "chai";
import { ethers } from "ethers";
import { deploy, getSigner } from "./helpers/setup.js";
import { concat, encodeAccountAmountBlock, encodeAccountAssetBlock, encodeAccountBalanceBlock, encodeBalanceBlock, encodeAssetAmountBlock, encodeBootstrapBlock, encodeContextBlock, encodeUserAccount } from "./helpers/blocks.js";
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

  const record = (account: string, amount: bigint, token = asset) =>
    concat("0x07", account, token, ethers.toBeHex(amount, 32));
  const logs = (receipt: any) => receipt.logs.map((log: any) => {
    expect(log.topics).deep.eq([]);
    return log.data;
  });

  async function balances() {
    return host.getBalance(concat(encodeAccountAssetBlock(hostAccount, asset), encodeAccountAssetBlock(user, asset)));
  }

  it("credits, debits, and queries host and user accounts through the same endpoints", async () => {
    for (const [method, input, amounts] of [
      ["portCreditAccount", concat(encodeAccountAmountBlock(hostAccount, asset, 100n), encodeAccountAmountBlock(user, asset, 40n)), [100n, 40n]],
      ["portDebitAccount", concat(encodeAccountAmountBlock(hostAccount, asset, 30n), encodeAccountAmountBlock(user, asset, 10n)), [70n, 30n]],
    ] as const) {
      const receipt = await (await host[method](input)).wait();
      expect(logs(receipt)).deep.eq([record(hostAccount, amounts[0]), record(user, amounts[1])]);
    }
    expect(await balances()).to.equal(concat(encodeAccountBalanceBlock(hostAccount, asset, 70n), encodeAccountBalanceBlock(user, asset, 30n)));
    for (const name of ["portCredit", "portDebit", "getAccountBalances"]) {
      expect(host.interface.getFunction(`${name}(bytes)`)).to.equal(null);
    }
  });

  it("logs each updated balance in order, skips zero mutations, and includes a final zero", async () => {
    const credits = concat(...[4n, 0n, 6n].map(n => encodeAccountAmountBlock(user, asset, n)));
    expect(logs(await (await host.portCreditAccount(credits)).wait())).deep.eq([record(user, 4n), record(user, 10n)]);
    const debits = concat(...[0n, 3n, 7n].map(n => encodeAccountAmountBlock(user, asset, n)));
    expect(logs(await (await host.portDebitAccount(debits)).wait())).deep.eq([record(user, 7n), record(user, 0n)]);
  });

  it("uses the same hook logs through ordinary and execute commands without duplicate lane logs", async () => {
    for (const optimized of [false, true]) {
      const state = encodeBalanceBlock(asset, 10n);
      const input = encodeAssetAmountBlock(asset, 10n);
      const credit = optimized ? host.execute(0, user, state, "0x", 0n)
        : host.creditAccount(encodeContextBlock(user, state, "0x"));
      expect(logs(await (await credit).wait())).deep.eq([record(user, 10n)]);
      const debit = optimized ? host.execute(1, user, "0x", input, 0n)
        : host.debitAccount(encodeContextBlock(user, "0x", input));
      const receipt = await (await debit).wait();
      expect(logs(receipt)).deep.eq([record(user, 0n)]);
    }
  });

  it("Bootstrap logs actual non-native and aggregated native balances through hooks", async () => {
    const native = await host.nativeAsset();
    await host.portCreditAccount(concat(encodeAccountAmountBlock(user, asset, 20n), encodeAccountAmountBlock(user, native, 20n)));
    const input = encodeBootstrapBlock(5n, concat(encodeAssetAmountBlock(native, 3n), encodeAssetAmountBlock(asset, 2n),
      encodeAssetAmountBlock(asset, 0n), encodeAssetAmountBlock(native, 4n)));
    const result = await host.execute.staticCall(2, user, "0x", input, 4n);
    expect(result[1]).eq(concat(encodeBalanceBlock(native, 3n), encodeBalanceBlock(asset, 2n),
      encodeBalanceBlock(asset, 0n), encodeBalanceBlock(native, 4n)));
    expect(result[2]).eq(5n);
    expect(logs(await (await host.execute(2, user, "0x", input, 4n)).wait())).deep.eq([
      record(user, 18n), record(user, 12n, native),
    ]);
  });

  it("rolls back an overflowing credit batch", async () => {
    await host.portCreditAccount(encodeAccountAmountBlock(user, asset, ethers.MaxUint256 - 1n));
    const before = await balances();
    let error: any;
    try { await host.portCreditAccount(concat(...[1n, 1n].map(n => encodeAccountAmountBlock(user, asset, n)))); }
    catch (caught) { error = caught; }
    expect(error?.data).eq("0x4e487b71" + ethers.toBeHex(0x11, 32).slice(2));
    expect(await balances()).eq(before);
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
