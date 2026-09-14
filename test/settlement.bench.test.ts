import { expect } from "chai";
import { ethers } from "ethers";
import { mkdirSync, writeFileSync } from "node:fs";
import { deploy } from "./helpers/setup.js";
import { packLimits, encodeUserAccount } from "./helpers/blocks.js";

describe("Exact settlement benchmark", function () {
  this.timeout(120_000);

  it("measures booking and account exchanges with empty and existing recipient balances", async () => {
    const account = encodeUserAccount("0x11");
    const external = encodeUserAccount("0x22");
    const asset = ethers.toBeHex(1n, 32);
    const liability = ethers.toBeHex(2n, 32);
    const rows: object[] = [];
    for (const existing of [false, true]) {
      for (const kind of ["Rootzero", "host", "external"] as const) {
        const samples: { gas: number; execution: number }[] = [];
        for (let sample = 0; sample < 3; sample++) {
          const ledger = await deploy("TestSettlementGas");
          const host = await ledger.hostAccount();
          const counterparty = kind === "Rootzero" ? ethers.ZeroHash : kind === "host" ? host : external;
          await ledger.seed(account, liability, 100_000n);
          if (kind !== "Rootzero") await ledger.seed(counterparty, asset, 200_000n);
          const initial = existing ? 1n : 0n;
          if (existing) {
            await ledger.seed(account, asset, initial);
            if (kind !== "Rootzero") await ledger.seed(counterparty, liability, initial);
          }
          const tx = await ledger.applyPosition(account,
            [asset, 100_000n, liability, 40_000n, counterparty], packLimits(100_000n, 40_000n));
          const receipt = await tx.wait();
          expect(receipt.status).to.equal(1);
          expect(await ledger.balance(account, asset)).to.equal(initial + 100_000n);
          expect(await ledger.balance(account, liability)).to.equal(60_000n);
          if (kind !== "Rootzero") {
            expect(await ledger.balance(counterparty, liability)).to.equal(initial + 40_000n);
            expect(await ledger.balance(counterparty, asset)).to.equal(100_000n);
          }
          if (kind !== "host") {
            expect(await ledger.balance(host, liability)).to.equal(0n);
            expect(await ledger.balance(host, asset)).to.equal(0n);
          }
          const intrinsic = 21_000 + ethers.getBytes(tx.data).reduce((sum, byte) => sum + (byte === 0 ? 4 : 16), 0);
          samples.push({ gas: Number(receipt.gasUsed), execution: Number(receipt.gasUsed) - intrinsic });
        }
        const median = (values: number[]) => values.sort((a, b) => a - b)[1]!;
        rows.push({ recipients: existing ? "existing" : "empty", counterparty: kind,
          transactionGas: median(samples.map(s => s.gas)), executionGas: median(samples.map(s => s.execution)), samples });
      }
    }
    mkdirSync(".npm-cache", { recursive: true });
    writeFileSync(".npm-cache/settlement-benchmark.json", JSON.stringify(rows, null, 2) + "\n");
    console.table(rows.map(({ samples, ...row }: any) => row));
  });
});
