import { expect } from "chai";
import { ethers } from "ethers";
import { deploy } from "./helpers/setup.js";
import { packLimits, MaxUint128, encodeUserAccount } from "./helpers/blocks.js";
import "./helpers/matchers.js";

describe("Settlement ledger", () => {
  const account = encodeUserAccount("0x11");
  const external = encodeUserAccount("0x22");
  const asset = ethers.toBeHex(1n, 32);
  const liability = ethers.toBeHex(2n, 32);
  let ledger: Awaited<ReturnType<typeof deploy>>;
  let host: string;

  beforeEach(async () => {
    ledger = await deploy("TestSettlement");
    host = await ledger.hostAccount();
    await ledger.seed(account, liability, 40_000n);
  });

  async function balances(counterparty = external, payer = account) {
    return Promise.all([payer, counterparty, host].flatMap(owner =>
      [ledger.balance(owner, asset), ledger.balance(owner, liability)]));
  }

  async function events(transaction: Promise<any>, name: string) {
    const receipt = await (await transaction).wait();
    return receipt.logs.map((log: any) => ledger.interface.parseLog(log))
      .filter((log: any) => log?.name === name).map((log: any) => Array.from(log.args));
  }

  for (const kind of ["user", "host", "remote host"] as const) {
    for (const exact of [true, false]) {
      it(`settles exact quantities against a ${kind} with ${exact ? "exact" : "roomy"} limits and no host fee`, async () => {
        const other = kind === "host" ? host : kind === "user" ? external
          : await (await deploy("TestSettlement")).hostAccount();
        await ledger.seed(other, asset, 100_000n);
        const limits = exact ? packLimits(100_000n, 40_000n) : packLimits(0n, MaxUint128);
        expect(await events(ledger.applyLimitedPosition(account,
          [asset, 100_000n, liability, 40_000n, other], limits), "AccountOperation")).to.deep.equal([
          [true, account, liability, 40_000n], [false, other, liability, 40_000n],
          [true, other, asset, 100_000n], [false, account, asset, 100_000n],
        ]);
        expect(await balances(other)).to.deep.equal([
          100_000n, 0n, 0n, 40_000n, 0n, kind === "host" ? 40_000n : 0n,
        ]);
      });
    }
  }

  it("routes both exact exchange legs through BookHook", async () => {
    await ledger.seed(external, asset, 100_000n);
    expect(await events(ledger.applyLimitedPosition(account,
      [asset, 100_000n, liability, 40_000n, external], packLimits(100_000n, 40_000n)), "Applied"))
      .to.deep.equal([
        [account, external, liability, 40_000n, liability, 40_000n],
        [external, account, asset, 100_000n, asset, 100_000n],
      ]);
  });

  it("books Rootzero quantities on the active account", async () => {
    expect(await events(ledger.applyLimitedPosition(account,
      [asset, 100_000n, liability, 40_000n, ethers.ZeroHash], packLimits(100_000n, 40_000n)), "AccountOperation"))
      .to.deep.equal([[true, account, liability, 40_000n], [false, account, asset, 100_000n]]);
    expect(await balances()).to.deep.equal([100_000n, 0n, 0n, 0n, 0n, 0n]);
  });

  for (const rootzero of [false, true]) {
    for (const [minimum, maximum] of [[100_001n, 40_000n], [100_000n, 39_999n]]) {
      it(`enforces ${minimum}/${maximum} limits before ${rootzero ? "booking" : "exchange"} transfers`, async () => {
        const before = await balances();
        await expect(ledger.applyLimitedPosition(account,
          [asset, 100_000n, liability, 40_000n, rootzero ? ethers.ZeroHash : external], packLimits(minimum, maximum)))
          .to.be.revertedWithCustomError(ledger, "OutOfRange");
        expect(await balances()).to.deep.equal(before);
      });
    }
  }

  for (const kind of ["Rootzero", "host", "user"] as const) {
    for (const [amount, debt] of [[0n, 0n], [0n, 1n], [1n, 0n], [1n, 1n]]) {
      it(`settles ${kind} quantities ${amount}/${debt} without rounding or fees`, async () => {
        const other = kind === "Rootzero" ? ethers.ZeroHash : kind === "host" ? host : external;
        if (other !== ethers.ZeroHash) await ledger.seed(other, asset, amount);
        const calls = await events(ledger.applyLimitedPosition(account,
          [amount ? asset : ethers.ZeroHash, amount, debt ? liability : ethers.ZeroHash, debt, other],
          packLimits(amount, debt)), "AccountOperation");
        expect(calls.length).to.equal(Number((amount ? 1n : 0n) + (debt ? 1n : 0n)) * (kind === "Rootzero" ? 1 : 2));
        expect(await ledger.balance(account, asset)).to.equal(amount);
        expect(await ledger.balance(account, liability)).to.equal(40_000n - debt);
      });
    }
  }

  for (const [amount, debt] of [[100_001n, 40_000n], [100_000n, 40_001n]]) {
    it(`rolls back both legs when ${amount}/${debt} exceeds available funds`, async () => {
      await ledger.seed(external, asset, 100_000n);
      const before = await balances();
      await expect(ledger.applyPosition(account, [asset, amount, liability, debt, external]))
        .to.be.revertedWithCustomError(ledger, "InsufficientFunds");
      expect(await balances()).to.deep.equal(before);
    });
  }

  it("keeps exact payments when the host is the payer", async () => {
    await ledger.seed(host, liability, 40_000n);
    await ledger.seed(external, asset, 100_000n);
    await ledger.applyLimitedPosition(host,
      [asset, 100_000n, liability, 40_000n, external], packLimits(100_000n, 40_000n));
    expect(await balances(external, host)).to.deep.equal([100_000n, 0n, 0n, 40_000n, 100_000n, 0n]);
  });

  for (const own of [false, true]) {
    it(`preserves balances for a funded ${own ? "host" : "user"} self-exchange and still enforces limits`, async () => {
      const payer = own ? host : account;
      if (own) await ledger.seed(payer, liability, 40_000n);
      await ledger.seed(payer, asset, 100_000n);
      const position = [asset, 100_000n, liability, 40_000n, payer];
      const before = await balances(payer, payer);
      await ledger.applyLimitedPosition(payer, position, packLimits(100_000n, 40_000n));
      expect(await balances(payer, payer)).to.deep.equal(before);
      await expect(ledger.applyLimitedPosition(payer, position, packLimits(100_001n, 40_000n)))
        .to.be.revertedWithCustomError(ledger, "OutOfRange");
      await expect(ledger.applyPosition(payer, [asset, 100_000n, liability, 40_001n, payer]))
        .to.be.revertedWithCustomError(ledger, "InsufficientFunds");
      expect(await balances(payer, payer)).to.deep.equal(before);
    });
  }

  it("settles debt first when both sides use the same asset", async () => {
    await ledger.applyPosition(account, [liability, 30_000n, liability, 40_000n, external]);
    expect(await ledger.balance(account, liability)).to.equal(30_000n);
    expect(await ledger.balance(external, liability)).to.equal(10_000n);
    expect(await ledger.balance(host, liability)).to.equal(0n);
  });

  it("cannot use incoming assets to fund the initial debt", async () => {
    await ledger.seed(external, liability, 50_000n);
    const before = await balances();
    await expect(ledger.applyPosition(account, [liability, 50_000n, liability, 40_001n, external]))
      .to.be.revertedWithCustomError(ledger, "InsufficientFunds");
    expect(await balances()).to.deep.equal(before);
  });

  for (const rootzero of [false, true]) {
    it(`accepts full-width asset output and the literal debt cap for ${rootzero ? "booking" : "exchange"}`, async () => {
      await ledger.seed(account, liability, MaxUint128 - 40_000n);
      if (!rootzero) await ledger.seed(external, asset, MaxUint128 + 1n);
      const other = rootzero ? ethers.ZeroHash : external;
      await ledger.applyLimitedPosition(account,
        [asset, MaxUint128 + 1n, liability, MaxUint128, other], packLimits(MaxUint128, MaxUint128));
      expect(await ledger.balance(account, asset)).to.equal(MaxUint128 + 1n);
      expect(await ledger.balance(account, liability)).to.equal(0n);
      expect(await ledger.balance(host, asset)).to.equal(0n);
      const before = await balances();
      await expect(ledger.applyLimitedPosition(account,
        [asset, MaxUint128 + 1n, liability, MaxUint128 + 1n, other], packLimits(MaxUint128, MaxUint128)))
        .to.be.revertedWithCustomError(ledger, "OutOfRange");
      expect(await balances()).to.deep.equal(before);
    });
  }

  it("leaves account formats to the host and skips account hooks for empty exchanges", async () => {
    const node = ethers.toBeHex((0x03020200n << 224n) | BigInt(await ledger.getAddress()), 32);
    for (const invalid of [asset, node]) {
      expect(await events(ledger.applyPosition(account, [asset, 0n, liability, 0n, invalid]), "AccountOperation"))
        .to.deep.equal([]);
    }
    await ledger.seed(asset, asset, 100n);
    await ledger.applyPosition(account, [asset, 100n, liability, 40n, asset]);
    expect(await ledger.balance(account, asset)).to.equal(100n);
    expect(await ledger.balance(asset, liability)).to.equal(40n);
  });

  it("checks limits even when account hooks are skipped", async () => {
    await expect(ledger.applyLimitedPosition(account,
      [asset, 0n, liability, 0n, asset], packLimits(1n, 0n)))
      .to.be.revertedWithCustomError(ledger, "OutOfRange");
  });

  it("lets debit and credit hooks reject accounts and rolls back prior transfers", async () => {
    const strict = await deploy("TestValidatedSettlement");
    await strict.seed(account, liability, 40n);
    await strict.seed(asset, asset, 100n);
    // Debt credit rejects the counterparty after debiting the active account.
    await expect(strict.applyPosition(account, [asset, 100n, liability, 40n, asset]))
      .to.be.revertedWithCustomError(strict, "InvalidAccount");
    expect(await strict.balance(account, liability)).to.equal(40n);
    // Asset-only settlement reaches the counterparty debit hook.
    await expect(strict.applyPosition(account, [asset, 100n, liability, 0n, asset]))
      .to.be.revertedWithCustomError(strict, "InvalidAccount");
    expect(await strict.balance(asset, asset)).to.equal(100n);
    // Empty exchanges do not invoke even a strict host's account hooks.
    await strict.applyPosition(account, [asset, 0n, liability, 0n, asset]);
  });
});
