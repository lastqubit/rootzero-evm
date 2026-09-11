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
  const position = [asset, 100_000n, liability, 40_000n, counterparty];
  let ledger: Awaited<ReturnType<typeof deploy>>;
  let hostAccount: string;

  beforeEach(async () => {
    ledger = await deploy("TestSettlement");
    hostAccount = await ledger.hostAccount();
    await ledger.seed(account, liability, 40_100n);
    await ledger.seed(counterparty, asset, 100_000n);
  });

  async function balances(other = counterparty) {
    return Promise.all([
      ledger.balance(account, asset), ledger.balance(account, liability),
      ledger.balance(other, asset), ledger.balance(other, liability),
      ledger.balance(hostAccount, asset), ledger.balance(hostAccount, liability),
    ]);
  }

  async function operations(transaction: Promise<any>) {
    const receipt = await (await transaction).wait();
    return receipt.logs.map((log: any) => ledger.interface.parseLog(log))
      .filter((log: any) => log?.name === "AccountOperation")
      .map((log: any) => Array.from(log.args));
  }

  for (const debtFee of [true, false]) {
    it(`routes transfers through BookHook and the separate ${debtFee ? "debt" : "asset"} fee through creditAccount`, async () => {
      const limits = debtFee ? [100_000n, 40_008n] : [99_980n, 40_000n];
      const receipt = await (await ledger.applyLimitedPosition(account, position, limits)).wait();
      const calls = receipt.logs.map((log: any) => ledger.interface.parseLog(log))
        .filter((log: any) => log?.name === "Applied").map((log: any) => Array.from(log.args));
      expect(calls).to.deep.equal(debtFee ? [
        [account, counterparty, liability, 40_000n, liability, 40_008n],
        [counterparty, account, asset, 100_000n, asset, 100_000n],
      ] : [
        [account, counterparty, liability, 40_000n, liability, 40_000n],
        [counterparty, account, asset, 99_980n, asset, 100_000n],
      ]);
      const hostCredits = receipt.logs.map((log: any) => ledger.interface.parseLog(log))
        .filter((log: any) => log?.name === "AccountOperation" && !log.args[0] && log.args[1] === hostAccount)
        .map((log: any) => Array.from(log.args));
      expect(hostCredits).to.deep.equal([
        [false, hostAccount, debtFee ? liability : asset, debtFee ? 8n : 20n],
      ]);
    });
  }

  it("returns the debt fee to a host payer without creating host revenue", async () => {
    await ledger.seed(hostAccount, liability, 40_100n);
    await ledger.applyLimitedPosition(hostAccount, position, [100_000n, 40_008n]);
    expect(await ledger.balance(hostAccount, liability)).to.equal(100n);
    expect(await ledger.balance(hostAccount, asset)).to.equal(100_000n);
    expect(await ledger.balance(counterparty, liability)).to.equal(40_000n);
    expect(await ledger.balance(counterparty, asset)).to.equal(0n);
  });

  it("credits both net assets and the fallback fee to a host payer", async () => {
    await ledger.seed(hostAccount, liability, 40_000n);
    await ledger.applyLimitedPosition(hostAccount, position, [99_980n, 40_000n]);
    expect(await ledger.balance(hostAccount, liability)).to.equal(0n);
    expect(await ledger.balance(hostAccount, asset)).to.equal(100_000n);
    expect(await ledger.balance(counterparty, liability)).to.equal(40_000n);
    expect(await ledger.balance(counterparty, asset)).to.equal(0n);
  });

  it("requires a host payer to fund the debt fee before it is credited back", async () => {
    await ledger.seed(hostAccount, liability, 40_000n);
    const before = await balances();
    await expect(ledger.applyLimitedPosition(hostAccount, position, [99_980n, 40_008n]))
      .to.be.revertedWithCustomError(ledger, "InsufficientFunds");
    expect(await balances()).to.deep.equal(before);
  });

  for (const limits of [[100_000n, 40_080n], [99_800n, 40_000n]]) {
    it(`preserves balances when payer and counterparty are the host at limits ${limits}`, async () => {
      await ledger.seed(hostAccount, liability, 40_100n);
      await ledger.seed(hostAccount, asset, 100_000n);
      const before = await balances();
      await ledger.applyLimitedPosition(hostAccount, [asset, 100_000n, liability, 40_000n, hostAccount], limits);
      expect(await balances()).to.deep.equal(before);
    });
  }

  it("still enforces fee limits when payer and counterparty are the host", async () => {
    await ledger.seed(hostAccount, liability, 40_100n);
    await ledger.seed(hostAccount, asset, 100_000n);
    const before = await balances();
    await expect(ledger.applyLimitedPosition(hostAccount, [asset, 100_000n, liability, 40_000n, hostAccount], [100_000n, 40_000n]))
      .to.be.revertedWithCustomError(ledger, "ZeroFee");
    expect(await balances()).to.deep.equal(before);
  });

  for (const tight of [false, true]) {
    it(`charges 2 bps for a user counterparty with ${tight ? "exact" : "roomy"} limits`, async () => {
      await ledger.applyLimitedPosition(account, position, tight ? [100_000n, 40_008n] : [0n, 50_000n]);
      expect(await balances()).to.deep.equal([100_000n, 92n, 0n, 40_000n, 0n, 8n]);
    });
  }

  it("charges 2 bps for another host's account", async () => {
    const other = await deploy("TestSettlement");
    const remote = await other.hostAccount();
    await ledger.seed(remote, asset, 100_000n);
    await ledger.applyLimitedPosition(account, [asset, 100_000n, liability, 40_000n, remote], [0n, 50_000n]);
    expect(await balances(remote)).to.deep.equal([100_000n, 92n, 0n, 40_000n, 0n, 8n]);
  });

  it("rejects a zero-amount position with a non-host counterparty because no fee can be collected", async () => {
    const before = await balances();
    await expect(ledger.applyLimitedPosition(account, [asset, 0n, liability, 0n, counterparty], [0n, 0n]))
      .to.be.revertedWithCustomError(ledger, "ZeroFee");
    expect(await balances()).to.deep.equal(before);
  });

  it("falls back to a 2 bps asset fee at the inclusive net minimum", async () => {
    await ledger.applyLimitedPosition(account, position, [99_980n, 40_000n]);
    expect(await balances()).to.deep.equal([99_980n, 100n, 0n, 40_000n, 20n, 0n]);
  });

  it("rejects external settlement when neither 2 bps fee fits", async () => {
    const before = await balances();
    await expect(ledger.applyLimitedPosition(account, position, [99_981n, 40_007n]))
      .to.be.revertedWithCustomError(ledger, "ZeroFee");
    expect(await balances()).to.deep.equal(before);
  });

  it("rejects a host fee if neither whole fee fits and rolls back repayment", async () => {
    await ledger.seed(hostAccount, asset, 100_000n);
    const before = await balances(hostAccount);
    await expect(ledger.applyLimitedPosition(account, [asset, 100_000n, liability, 40_000n, hostAccount], [99_801n, 40_079n]))
      .to.be.revertedWithCustomError(ledger, "ZeroFee");
    expect(await balances(hostAccount)).to.deep.equal(before);
  });

  it("collects exactly 20 bps on debt at the inclusive maximum", async () => {
    await ledger.seed(hostAccount, asset, 100_000n);
    await ledger.applyLimitedPosition(account, [asset, 100_000n, liability, 40_000n, hostAccount], [100_000n, 40_080n]);
    expect(await balances(hostAccount)).to.deep.equal([100_000n, 20n, 0n, 40_080n, 0n, 40_080n]);
  });

  it("falls back to assets at the inclusive net minimum", async () => {
    await ledger.seed(hostAccount, asset, 100_000n);
    await ledger.applyLimitedPosition(account, [asset, 100_000n, liability, 40_000n, hostAccount], [99_800n, 40_000n]);
    expect(await balances(hostAccount)).to.deep.equal([99_800n, 100n, 200n, 40_000n, 200n, 40_000n]);
  });

  it("charges only the debt fee when both sides have room", async () => {
    await ledger.seed(hostAccount, asset, 100_000n);
    await ledger.applyLimitedPosition(account, [asset, 100_000n, liability, 40_000n, hostAccount], [99_800n, 40_080n]);
    expect(await balances(hostAccount)).to.deep.equal([100_000n, 20n, 0n, 40_080n, 0n, 40_080n]);
  });

  for (const [limits, error] of [
    [[100_001n, 40_100n], "AmountOutOfRange"],
    [[0n, 39_999n], "AmountOutOfRange"],

  ] as const) {
    it(`reverts atomically for limits ${limits}`, async () => {
      const before = await balances();
      await expect(ledger.applyLimitedPosition(account, position, limits))
        .to.be.revertedWithCustomError(ledger, error);
      expect(await balances()).to.deep.equal(before);
    });
  }

  it("checks the asset minimum even when the asset amount is zero", async () => {
    const before = await balances();
    await expect(ledger.applyLimitedPosition(account, [ethers.ZeroHash, 0n, liability, 40_000n, counterparty], [1n, 40_100n]))
      .to.be.revertedWithCustomError(ledger, "AmountOutOfRange");
    expect(await balances()).to.deep.equal(before);
  });

  it("collects a one-unit debt fee below 400 raw units", async () => {
    await ledger.seed(hostAccount, asset, 100_000n);
    await ledger.applyPosition(account, [asset, 100n, liability, 40n, hostAccount]);
    expect(await balances(hostAccount)).to.deep.equal([100n, 40_059n, 99_900n, 41n, 99_900n, 41n]);
  });

  it("falls back to a one-unit asset fee below 400 raw units", async () => {
    await ledger.seed(hostAccount, asset, 100_000n);
    await ledger.applyLimitedPosition(account, [asset, 100n, liability, 40n, hostAccount], [99n, 40n]);
    expect(await balances(hostAccount)).to.deep.equal([99n, 40_060n, 99_901n, 40n, 99_901n, 40n]);
  });

  for (const [amount, debt] of [[0n, 0n], [0n, 40n], [100n, 0n], [100n, 40n]]) {
    it(`rejects a fee with no limit room for ${amount} assets and ${debt} debt`, async () => {
      const before = await balances();
      await expect(ledger.applyLimitedPosition(account, [asset, amount, liability, debt, hostAccount], [amount, debt]))
        .to.be.revertedWithCustomError(ledger, "ZeroFee");
      expect(await balances()).to.deep.equal(before);
    });
  }

  it("combines debt and fee into one host credit", async () => {
    await ledger.seed(hostAccount, asset, 100_000n);
    expect(await operations(ledger.applyPosition(account, [asset, 100_000n, liability, 40_000n, hostAccount])))
      .to.deep.equal([
        [true, account, liability, 40_080n], [false, hostAccount, liability, 40_080n],
        [true, hostAccount, asset, 100_000n], [false, account, asset, 100_000n],
      ]);
    expect(await balances(hostAccount)).to.deep.equal([100_000n, 20n, 0n, 40_080n, 0n, 40_080n]);
  });

  it("nets an asset fee retained by the host into one debit", async () => {
    await ledger.seed(hostAccount, asset, 100_000n);
    expect(await operations(ledger.applyLimitedPosition(
      account, [asset, 100_000n, liability, 40_000n, hostAccount], [99_800n, 40_000n],
    ))).to.deep.equal([
      [true, account, liability, 40_000n], [false, hostAccount, liability, 40_000n],
      [true, hostAccount, asset, 99_800n], [false, account, asset, 99_800n],
    ]);
    expect(await balances(hostAccount)).to.deep.equal([99_800n, 100n, 200n, 40_000n, 200n, 40_000n]);
  });

  it("skips transfers when the host retains a one-unit asset entirely as its fee", async () => {
    await ledger.seed(hostAccount, asset, 1n);
    expect(await operations(ledger.applyPosition(account, [asset, 1n, ethers.ZeroHash, 0n, hostAccount])))
      .to.deep.equal([]);
    expect(await ledger.balance(hostAccount, asset)).to.equal(1n);
  });

  it("collects a rounded one-unit asset fee from another counterparty", async () => {
    await ledger.applyPosition(account, [asset, 1n, ethers.ZeroHash, 0n, counterparty]);
    expect(await balances()).to.deep.equal([0n, 40_100n, 99_999n, 0n, 1n, 0n]);
  });

  for (const [amount, debt] of [[100_001n, 40_000n], [100_000n, 40_101n]]) {
    it(`rolls back all transfers when funds are insufficient for ${amount} and ${debt}`, async () => {
      const before = await balances();
      await expect(ledger.applyPosition(account, [asset, amount, liability, debt, counterparty]))
        .to.be.revertedWithCustomError(ledger, "InsufficientFunds");
      expect(await balances()).to.deep.equal(before);
    });
  }

  it("derives the host account from the deployed address", async () => {
    const utils = await deploy("TestUtils");
    expect(hostAccount).to.equal(await utils.testToHostAccount(await ledger.getAddress()));
  });

  for (const invalid of [ethers.ZeroHash, asset]) {
    it(`rejects an invalid counterparty ${invalid}`, async () => {
      const before = await balances();
      await expect(ledger.applyPosition(account, [asset, 0n, liability, 0n, invalid]))
        .to.be.revertedWithCustomError(ledger, "InvalidAccount");
      expect(await balances()).to.deep.equal(before);
    });
  }

  it("rejects a host node used as a counterparty", async () => {
    const node = ethers.toBeHex((0x03020200n << 224n) | BigInt(await ledger.getAddress()), 32);
    await expect(ledger.applyPosition(account, [asset, 0n, liability, 0n, node]))
      .to.be.revertedWithCustomError(ledger, "InvalidAccount");
  });

  it("settles liability-only and asset-only positions with fees", async () => {
    await ledger.seed(hostAccount, asset, 100_000n);
    await ledger.applyPosition(account, [ethers.ZeroHash, 0n, liability, 40_000n, hostAccount]);
    await ledger.applyPosition(account, [asset, 100_000n, ethers.ZeroHash, 0n, hostAccount]);
    expect(await balances(hostAccount)).to.deep.equal([99_800n, 20n, 200n, 40_080n, 200n, 40_080n]);
  });

  it("settles liability first when both sides use the same asset", async () => {
    await ledger.applyPosition(account, [liability, 30_000n, liability, 40_000n, counterparty]);
    expect(await balances()).to.deep.equal([0n, 30_092n, 100_000n, 10_000n, 0n, 8n]);
  });

  it("charges 2 bps when a non-host account is its own counterparty", async () => {
    await ledger.applyPosition(account, [liability, 30_000n, liability, 40_000n, account]);
    expect(await ledger.balance(account, liability)).to.equal(40_092n);
    expect(await ledger.balance(hostAccount, liability)).to.equal(8n);
  });
});
