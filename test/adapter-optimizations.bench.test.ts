import { expect } from "chai";
import { ethers } from "ethers";
import { deploy } from "./helpers/setup.js";
import { concat, encodeBalanceBlock, encodeBootstrapBlock, encodeAssetAmountBlock, encodeBalanceConstraintsBlock } from "./helpers/blocks.js";

describe("Balance and bootstrap adapter gas", function () {
  this.timeout(120_000);
  it("measures each adapter and their composition with identical funding", async () => {
    const host = await deploy("TestAdapterOptimizations");
    const asset = ethers.toBeHex(1n, 32);
    await (await host.seed(asset, ethers.MaxUint256)).wait();
    await (await host.seed(await host.nativeAsset(), ethers.MaxUint256)).wait();
    const rows: { count: number; balance: number; bootstrap: number; both: number }[] = [];
    for (const count of [0, 1, 2, 4, 8, 16, 32]) {
      const state = concat(...Array(count).fill(encodeBalanceBlock(asset, 100n)));
      const input = encodeBootstrapBlock(3n, concat(...Array(count).fill(encodeAssetAmountBlock(asset, 100n))));
      const limits = concat(...Array(count).fill(encodeBalanceConstraintsBlock(asset, 90n, 110n)));
      const balance = await host.measureBalance(state, limits, 7n);
      const bootstrap = await host.measureBootstrap.staticCall("0x", input, 7n);
      const both = await host.measureBoth.staticCall(input, limits, 7n);
      expect(Array.from(balance).slice(1)).to.deep.equal([true, state, 7n]);
      for (const result of [bootstrap, both]) {
        expect(Array.from(result).slice(1)).to.deep.equal([true, state, 7n]);
      }
      rows.push({ count, balance: Number(balance[0]), bootstrap: Number(bootstrap[0]), both: Number(both[0]) });
    }
    // Internal gasleft measurements exclude external calldata/return encoding costs.
    console.table(rows);
  });

  it("measures repeated chainAsset requests with one aggregate debit", async () => {
    const host = await deploy("TestAdapterOptimizations");
    const native = await host.nativeAsset();
    await host.seed(native, ethers.MaxUint256);
    const rows: { count: number; value: number; gas: number }[] = [];
    for (const count of [0, 1, 2, 4, 8, 16, 32]) {
      const input = encodeBootstrapBlock(5n, concat(...Array(count).fill(encodeAssetAmountBlock(native, 10n))));
      for (const value of [0n, 10n * BigInt(count) + 5n]) {
        const result = await host.measureBootstrap.staticCall("0x", input, value);
        expect(result[2]).eq(concat(...Array(count).fill(encodeBalanceBlock(native, 10n))));
        expect(result[3]).eq(5n);
        rows.push({ count, value: Number(value), gas: Number(result[0]) });
      }
    }
    // Includes storage accesses and the test hook's Debited event when a debit occurs.
    console.table(rows);
  });
});
