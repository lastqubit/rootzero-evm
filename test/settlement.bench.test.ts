import { expect } from "chai";
import { ethers } from "ethers";
import { mkdirSync, writeFileSync } from "node:fs";
import { deploy } from "./helpers/setup.js";
import { encodeUserAccount } from "./helpers/blocks.js";

describe("Settlement fee path benchmark", function () {
  this.timeout(120_000);

  it("measures four fee paths with empty and existing recipient balances", async () => {
    const account = encodeUserAccount("0x11");
    const external = encodeUserAccount("0x22");
    const asset = ethers.toBeHex(1n, 32);
    const liability = ethers.toBeHex(2n, 32);
    const rows: object[] = [];
    for (const existing of [false, true]) {
      for (const own of [true, false]) {
        for (const debtFee of [true, false]) {
          const samples: { gas: number; execution: number }[] = [];
          for (let sample = 0; sample < 3; sample++) {
            const ledger = await deploy("TestSettlementGas");
            const host = await ledger.hostAccount();
            const counterparty = own ? host : external;
            // Debited balances remain nonzero, so no storage-clearing refunds apply.
            await ledger.seed(account, liability, 100_000n);
            await ledger.seed(counterparty, asset, 200_000n);
            if (existing) {
              await ledger.seed(account, asset, 1n);
              await ledger.seed(counterparty, liability, 1n);
              if (!own) {
                await ledger.seed(host, asset, 1n);
                await ledger.seed(host, liability, 1n);
              }
            }
            const debtCharge = own ? 80n : 8n;
            const assetCharge = own ? 200n : 20n;
            const limits = debtFee ? [100_000n, 40_000n + debtCharge] : [100_000n - assetCharge, 40_000n];
            const tx = await ledger.applyPosition(account, [asset, 100_000n, liability, 40_000n, counterparty], limits);
            const receipt = await tx.wait();
            expect(receipt.status).to.equal(1);
            const initial = existing ? 1n : 0n;
            expect(await ledger.balance(account, asset)).to.equal(initial + 100_000n - (debtFee ? 0n : assetCharge));
            expect(await ledger.balance(account, liability)).to.equal(60_000n - (debtFee ? debtCharge : 0n));
            expect(await ledger.balance(counterparty, liability)).to.equal(initial + 40_000n + (own && debtFee ? debtCharge : 0n));
            expect(await ledger.balance(counterparty, asset)).to.equal(100_000n + (own && !debtFee ? assetCharge : 0n));
            if (!own) {
              expect(await ledger.balance(host, liability)).to.equal(initial + (debtFee ? debtCharge : 0n));
              expect(await ledger.balance(host, asset)).to.equal(initial + (debtFee ? 0n : assetCharge));
            }
            const intrinsic = 21_000 + ethers.getBytes(tx.data).reduce((sum, byte) => sum + (byte === 0 ? 4 : 16), 0);
            samples.push({ gas: Number(receipt.gasUsed), execution: Number(receipt.gasUsed) - intrinsic });
          }
          const median = (values: number[]) => values.sort((a, b) => a - b)[1]!;
          rows.push({ recipients: existing ? "existing" : "empty", counterparty: own ? "host" : "external",
            feeSide: debtFee ? "debt" : "asset", transactionGas: median(samples.map(s => s.gas)),
            executionGas: median(samples.map(s => s.execution)), samples });
        }
      }
    }
    mkdirSync(".npm-cache", { recursive: true });
    writeFileSync(".npm-cache/settlement-benchmark.json", JSON.stringify(rows, null, 2) + "\n");
    console.table(rows.map(({ samples, ...row }: any) => row));
  });
});
