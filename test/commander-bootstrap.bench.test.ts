import { expect } from "chai";
import { ethers } from "ethers";
import { mkdirSync, writeFileSync } from "node:fs";
import { deploy } from "./helpers/setup.js";
import { concat, encodeBlock, encodeBootstrapBlock, encodeAssetAmountBlock, encodeBalanceBlock, Keys } from "./helpers/blocks.js";
import { decodeBlockLog } from "./helpers/log-blocks.js";

describe("Commander Bootstrap migration", function () {
  this.timeout(120_000);
  it("compares installed 1.48 funding and events against the frozen v1.51 adapter", async () => {
    const old = await deploy("CommanderHistoricalBootstrap"), current = await deploy("CommanderCurrentBootstrap");
    const native = await current.nativeAsset(), account = ethers.id("commander-bootstrap-account");
    const initial = 1_000_000n;
    const assets = [native, ...Array.from({ length: 16 }, (_, i) => ethers.id(`bootstrap-asset-${i}`))];
    const rows: any[] = [];
    for (const kind of ["other", "native", "native-funded"]) {
      for (const count of [1, 2, 4, 8, 16]) {
        const requested = Array.from({ length: count }, (_, i) => kind === "other" ? assets[i + 1] : native);
        // A single final budget contribution makes old and new final funding equal.
        // Funded cases use budget zero, preserving equality despite changed budget semantics.
        const funded = kind === "native-funded";
        const budget = funded ? 0n : 5n, value = funded ? BigInt(count) * 10n + 5n : 0n;
        const legacyInput = concat(...requested.map((asset, i) => encodeBlock(Keys.Bootstrap,
          concat(asset, ethers.toBeHex(10n, 32), ethers.toBeHex(i === count - 1 ? budget : 0n, 32)))));
        const input = encodeBootstrapBlock(budget, concat(...requested.map(asset => encodeAssetAmountBlock(asset, 10n))));
        const output = concat(...requested.map(asset => encodeBalanceBlock(asset, 10n)));
        const gas: bigint[] = [], receiptGas: bigint[] = [], logs: number[] = [];
        for (const [index, host] of [old, current].entries()) {
          await (await host.seed(account, assets, initial)).wait();
          const data = index === 0 ? legacyInput : input;
          const result = await host.measure.staticCall(account, data, value);
          expect(result[1]).eq(output);
          expect(result[2]).eq(5n);
          gas.push(result[0]);
          const receipt = await (await host.measure(account, data, value)).wait();
          receiptGas.push(receipt.gasUsed); logs.push(receipt.logs.length);
          for (const asset of new Set([native, ...requested])) {
            const debit = asset === native ? (funded ? 0n : budget + (kind === "native" ? BigInt(count) * 10n : 0n)) : 10n;
            expect(await host.balanceOf(account, asset)).eq(initial - debit);
          }
          if (index === 0) {
            expect(receipt.logs.length).eq(funded ? 0 : kind === "other" ? count + 1 : count);
            const ledger = new Map(assets.map(asset => [asset, initial]));
            const expected: any[] = [];
            const debit = (asset: string, amount: bigint) => {
              if (!amount) return;
              const next = ledger.get(asset)! - amount; ledger.set(asset, next);
              expected.push([account, asset, next]);
            };
            requested.forEach((asset, i) => {
              if (!funded) {
                if (asset === native) debit(native, 10n + (i === count - 1 ? budget : 0n));
                else { debit(asset, 10n); if (i === count - 1) debit(native, budget); }
              }
            });
            expect(receipt.logs.map((log: any) => host.interface.parseLog(log).args.toArray())).deep.eq(expected);
          } else {
            const stream = concat(
              ...(kind === "other" ? requested.map(asset => encodeBalanceBlock(asset, 10n)) : []),
              encodeBalanceBlock(native, budget + (kind === "native" ? BigInt(count) * 10n : 0n)),
            );
            expect(receipt.logs.map((log: any) => decodeBlockLog(log))).deep.eq(funded ? [] : [{
              prefix: 0x20000001n | (72n << 32n), stream,
            }]);
          }
        }
        rows.push({ kind, count, oldGas: Number(gas[0]), newGas: Number(gas[1]), saved: Number(gas[0] - gas[1]),
          oldReceipt: Number(receiptGas[0]), newReceipt: Number(receiptGas[1]), receiptSaved: Number(receiptGas[0] - receiptGas[1]),
          oldLogs: logs[0], newLogs: logs[1], oldInputBytes: ethers.dataLength(legacyInput), newInputBytes: ethers.dataLength(input) });
      }
    }
    mkdirSync(".npm-cache", { recursive: true });
    writeFileSync(".npm-cache/commander-bootstrap-gas.json", JSON.stringify(rows, null, 2));
    console.table(rows);
    for (const row of rows.filter(row => row.kind !== "native-funded" && row.count >= 4)) expect(row.saved).greaterThan(0);
  });
});
