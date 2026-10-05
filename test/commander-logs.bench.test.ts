import { expect } from "chai";
import { ethers } from "ethers";
import { mkdirSync, writeFileSync } from "node:fs";
import { deploy } from "./helpers/setup.js";
import { concat, encodeAssetAmountBlock, encodeBalanceBlock, encodeBootstrapBlock,
  encodeInputBlock, encodeOutputBlock, encodeStateBlock, encodePipelineBlock } from "./helpers/blocks.js";

const account = ethers.id("commander-log-account");
const initial = 1_000_000n;
const endpoint = 0x03020300n << 224n;
const scope = 0x20000001n;
const prefix = (code: bigint, stream: string) => concat(ethers.toBeHex(code, 32), stream);

describe("Commander logging comparison", function () {
  this.timeout(180_000);
  it("compares identical ledger work with legacy events, block logs, and no logs", async () => {
    const hosts = await Promise.all(["CommanderLegacyLogs", "CommanderBlockLogs", "CommanderNoLogs"].map(name => deploy(name)));
    const native = await hosts[0].nativeAsset();
    const assets = [native, ...Array.from({ length: 16 }, (_, i) => ethers.id(`commander-asset-${i}`))];
    const rows: any[] = [];
    for (const workload of ["credit", "debit", "bootstrap-other", "bootstrap-native", "bootstrap-funded", "roundtrip-other", "roundtrip-native", "cashin", "root"]) {
      for (const count of (workload === "cashin" || workload === "root" ? [1] : [0, 1, 2, 4, 8, 16])) {
        const mode = workload === "credit" ? 0 : workload === "debit" ? 1 : workload.startsWith("bootstrap") ? 2 : workload === "cashin" ? 3 : workload === "root" ? 4 : 5;
        const isNative = workload.endsWith("native") || workload.endsWith("funded");
        const requested = Array.from({ length: count }, (_, i) => ({ asset: isNative ? native : assets[i + 1], amount: 10n }));
        const amounts = concat(...requested.map(x => encodeAssetAmountBlock(x.asset, x.amount)));
        const balances = concat(...requested.map(x => encodeBalanceBlock(x.asset, x.amount)));
        const input = mode === 0 ? balances : mode === 1 ? amounts : mode === 2 || mode === 5 ? encodeBootstrapBlock(5n, amounts) : "0x";
        const value = workload === "bootstrap-funded" ? BigInt(count) * 10n + 5n : mode === 3 || mode === 4 ? 5n : 0n;
        const ledger = new Map(assets.map(a => [a, initial]));
        const oldEvents: any[] = [], newLogs: string[] = [];
        const change = (asset: string, delta: bigint) => {
          if (!delta) return;
          const next = ledger.get(asset)! + delta;
          ledger.set(asset, next);
          oldEvents.push(["Balance", account, asset, next]);
        };
        const logBalance = (amount: bigint, action: bigint) => prefix(scope | (action << 32n), encodeBalanceBlock(native, amount));
        const credit = () => {
          newLogs.push(prefix(endpoint | 1n, encodeStateBlock(balances)));
          for (const x of requested) change(x.asset, x.amount);
        };
        const cashin = (amount: bigint) => {
          if (!amount) return;
          change(native, amount);
          oldEvents.push(["Activity", account, native, amount, 36n | (0x80000001n << 32n)]);
          newLogs.push(logBalance(amount, 36n));
        };
        let expectedOutput = "0x", remaining = 0n;
        if (mode === 4 || mode === 5) newLogs.push(prefix(scope, encodePipelineBlock(account, value)));
        if (mode === 0) credit();
        if (mode === 1) {
          for (const x of requested) change(x.asset, -x.amount);
          expectedOutput = balances;
          newLogs.push(prefix(endpoint | 2n, encodeOutputBlock(balances)));
        }
        if (mode === 2 || mode === 5) {
          expectedOutput = balances;
          newLogs.push(prefix(endpoint | 3n, encodeInputBlock(input)));
          const nativeTotal = requested.filter(x => x.asset === native).reduce((sum, x) => sum + x.amount, 0n);
          for (const x of requested) if (x.asset !== native) change(x.asset, -x.amount);
          const funded = nativeTotal < value ? nativeTotal : value;
          remaining = value - funded;
          let debit = nativeTotal - funded;
          if (remaining < 5n) { debit += 5n - remaining; remaining = 5n; }
          if (debit) { change(native, -debit); newLogs.push(logBalance(debit, 71n)); }
          if (mode === 5) { credit(); cashin(remaining); }
        }
        if (mode === 3) cashin(value);
        if (mode === 4 || mode === 5) oldEvents.push(["Rooted", account, 0n, value]);
        const used: bigint[] = [], receipts: bigint[] = [];
        for (const [variant, host] of hosts.entries()) {
          await (await host.seed(account, assets, initial)).wait();
          const result = await host.measure.staticCall(mode, account, input, value);
          expect(result[1], workload).eq(expectedOutput);
          expect(result[2], workload).eq(remaining);
          used.push(result[0]);
          const receipt = await (await host.measure(mode, account, input, value)).wait();
          receipts.push(receipt.gasUsed);
          for (const asset of new Set([native, ...requested.map(x => x.asset)])) {
            expect(await host.balanceOf(account, asset), workload).eq(ledger.get(asset));
          }
          if (variant === 0) {
            expect(receipt.logs.map((log: any) => {
              const parsed = host.interface.parseLog(log);
              return [parsed.name, ...parsed.args.toArray()];
            }), workload).deep.eq(oldEvents);
          } else if (variant === 1) {
            expect(receipt.logs.every((log: any) => log.topics.length === 0)).eq(true);
            expect(receipt.logs.map((log: any) => log.data), workload).deep.eq(newLogs);
          } else expect(receipt.logs.length).eq(0);
        }
        rows.push({ workload, count, oldGas: Number(used[0]), newGas: Number(used[1]),
          saved: Number(used[0] - used[1]), oldLogging: Number(used[0] - used[2]), newLogging: Number(used[1] - used[2]),
          oldLogs: oldEvents.length, newLogs: newLogs.length,
          oldReceipt: Number(receipts[0]), newReceipt: Number(receipts[1]), receiptSaved: Number(receipts[0] - receipts[1]) });
      }
    }
    mkdirSync(".npm-cache", { recursive: true });
    writeFileSync(".npm-cache/commander-logs-gas.json", JSON.stringify(rows, null, 2));
    console.table(rows.filter(row => [1, 4, 16].includes(row.count)));
    // Batch and cashin savings are expected; fully funded native requests and
    // empty operations may cost more because they now have an explicit input log.
    for (const row of rows.filter(row => ["credit", "debit", "roundtrip-other", "cashin"].includes(row.workload) && row.count >= 1)) {
      expect(row.saved, JSON.stringify(row)).greaterThan(0);
    }
  });
});
