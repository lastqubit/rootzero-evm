import { expect } from "chai";
import { ethers } from "ethers";
import { mkdirSync, writeFileSync } from "node:fs";
import { deploy } from "./helpers/setup.js";
import { concat, encodeAssetAmountBlock, encodeBalanceBlock, encodeBootstrapBlock,
  encodeInputBlock } from "./helpers/blocks.js";
import { decodeBlockLog } from "./helpers/log-blocks.js";

const account = ethers.id("bootstrap-debit-writer-account");
const initial = 1_000_000n;
const bootstrapCodes = 0x20000001n | (72n << 32n);
const debitCodes = 0x20000001n | (71n << 32n);

describe("Bootstrap actual-debit event writer", function () {
  this.timeout(240_000);
  it("compares input logging with preallocated and hybrid debit writers and verifies all emitted data", async () => {
    const hosts = await Promise.all(["CommanderInputBootstrap", "BootstrapDebitLogWriter", "BootstrapDebitLogReserved", "CommanderCurrentBootstrap"].map(name => deploy(name)));
    const native = await hosts[0].nativeAsset();
    const assets = [native, ...Array.from({ length: 32 }, (_, i) => ethers.id(`debit-writer-asset-${i}`))];
    const rows: any[] = [];
    for (const kind of ["other-budget", "other-no-budget", "native", "native-funded", "mixed", "native-first", "native-last", "zero", "zero-first", "zero-last"]) {
      for (const count of [0, 1, 2, 4, 8, 16, 32]) {
        const requested = Array.from({ length: count }, (_, i) => {
          const useNative = kind === "native" || kind === "native-funded"
            || (kind === "native-first" && i === 0)
            || (kind === "native-last" && i === count - 1)
            || (kind === "mixed" && i % 2 === 0);
          const zero = kind === "zero" || (kind === "zero-first" && i === 0)
            || (kind === "zero-last" && i === count - 1);
          return { asset: useNative ? native : assets[i + 1], amount: zero ? 0n : 10n };
        });
        const budget = kind === "other-no-budget" || kind.startsWith("zero") ? 0n : 5n;
        const nativeTotal = requested.filter(x => x.asset === native).reduce((sum, x) => sum + x.amount, 0n);
        const value = kind === "native-funded" ? nativeTotal + budget : kind === "mixed" ? 7n : 0n;
        const funded = nativeTotal < value ? nativeTotal : value;
        const credit = value - funded > budget ? value - funded : budget;
        const nativeDebit = nativeTotal - funded + credit - (value - funded);
        const amounts = concat(...requested.map(x => encodeAssetAmountBlock(x.asset, x.amount)));
        const input = encodeBootstrapBlock(budget, amounts);
        const output = concat(...requested.map(x => encodeBalanceBlock(x.asset, x.amount)));
        const debits = requested.filter(x => x.asset !== native && x.amount !== 0n);
        if (nativeDebit) debits.push({ asset: native, amount: nativeDebit });
        const debitStream = concat(...debits.map(x => encodeBalanceBlock(x.asset, x.amount)));
        const ledger = new Map(assets.map(asset => [asset, initial]));
        for (const x of debits) ledger.set(x.asset, ledger.get(x.asset)! - x.amount);
        const gas: number[] = [], receipts: number[] = [], counts: number[] = [], bytes: number[] = [];
        for (const [variant, host] of hosts.entries()) {
          await (await host.seed(account, assets, initial)).wait();
          const result = await host.measure.staticCall(account, input, value);
          expect(result[1], kind).eq(output);
          expect(result[2], kind).eq(credit);
          gas.push(Number(result[0]));
          const receipt = await (await host.measure(account, input, value)).wait();
          receipts.push(Number(receipt.gasUsed)); counts.push(receipt.logs.length);
          bytes.push(receipt.logs.reduce((sum: number, log: any) => sum + ethers.dataLength(log.data), 0));
          for (const asset of new Set([native, ...requested.map(x => x.asset)])) {
            expect(await host.balanceOf(account, asset), kind).eq(ledger.get(asset));
          }
          expect(receipt.logs.every((log: any) => log.topics.length === 0)).eq(true);
          const records = receipt.logs.map((log: any) => decodeBlockLog(log));
          if (variant === 0) {
            expect(records.length).eq(nativeDebit ? 2 : 1);
            expect(records[0].stream).eq(encodeInputBlock(input));
            if (nativeDebit) expect(records[1]).deep.eq({ prefix: debitCodes, stream: encodeBalanceBlock(native, nativeDebit) });
          } else {
            expect(records).deep.eq(debits.length ? [{ prefix: bootstrapCodes, stream: debitStream }] : []);
          }
        }
        rows.push({ kind, count, debits: debits.length, input: gas[0], writer: gas[1], reserved: gas[2], hybrid: gas[3],
          writerSaved: gas[0] - gas[1], reservedSaved: gas[0] - gas[2], hybridSaved: gas[0] - gas[3],
          inputReceipt: receipts[0], writerReceipt: receipts[1], reservedReceipt: receipts[2], hybridReceipt: receipts[3],
          inputLogs: counts[0], writerLogs: counts[1], reservedLogs: counts[2], hybridLogs: counts[3],
          inputBytes: bytes[0], debitBytes: bytes[1] });
      }
    }
    mkdirSync(".npm-cache", { recursive: true });
    writeFileSync(".npm-cache/bootstrap-debit-logs-gas.json", JSON.stringify(rows, null, 2));
    console.table(rows.filter(row => [1, 4, 16, 32].includes(row.count)).map(({kind, count, input, writer, reserved, hybrid, writerSaved, reservedSaved, hybridSaved}) =>
      ({kind, count, input, writer, reserved, hybrid, writerSaved, reservedSaved, hybridSaved})));
  });
});
