import { expect } from "chai";
import { ethers } from "ethers";
import { deploy } from "./helpers/setup.js";
import { concat, encodeBalanceBlock, encodeBootstrapBlock, encodeAssetAmountBlock, encodeBalanceConstraintsBlock } from "./helpers/blocks.js";
import "./helpers/matchers.js";

describe("Balance and bootstrap adapter boundaries", () => {
  const asset = ethers.toBeHex(1n, 32);
  const balance = encodeBalanceBlock(asset, 100n);
  const bootstrap = encodeBootstrapBlock(3n, encodeAssetAmountBlock(asset, 100n));
  const limits = encodeBalanceConstraintsBlock(asset, 100n, 100n);
  let host: any;
  let native: string;
  async function expectOverflow(call: Promise<unknown>) {
    try {
      await call;
    } catch (error: any) {
      expect(error.data ?? error.error?.data ?? error.info?.error?.data)
        .to.equal(concat("0x4e487b71", ethers.toBeHex(0x11, 32)));
      return;
    }
    throw new Error("Expected arithmetic overflow");
  }
  beforeEach(async () => {
    host = await deploy("TestAdapterOptimizations");
    native = await host.nativeAsset();
    await host.seed(asset, 10_000n);
    await host.seed(native, 10_000n);
  });

  it("preserves empty balance streams and unused assigned value", async () => {
    for (const value of [0n, 1n, ethers.MaxUint256]) {
      for (const result of [
        await host.measureBalance("0x", "0x", value),
        await host.measureBootstrap.staticCall("0x", encodeBootstrapBlock(0n), value),
        await host.measureBoth.staticCall(encodeBootstrapBlock(0n), "0x", value),
      ]) expect(Array.from(result).slice(1)).to.deep.equal([true, "0x", value]);
      expect(Array.from(await host.measureBalance(balance, limits, value)).slice(1))
        .to.deep.equal([true, balance, value]);
    }
  });

  it("rejects partial balance and limits streams at header and payload boundaries", async () => {
    for (const size of [1, 7, 8, 9, 39, 40, 71, 73]) {
      const partial = ethers.dataSlice(concat(balance, balance), 0, size);
      await expect(host.measureBalance(partial, limits, 0n)).to.be.revertedWithCustomError(host, "InvalidBlock");
    }
    for (const size of [1, 7, 8, 9, 39, 40, 71, 72, 103, 105]) {
      const partial = ethers.dataSlice(concat(limits, limits), 0, size);
      // Even when floor(input.length / 104) matches state, partial input must fail.
      for (const state of ["0x", balance]) {
        await expect(host.measureBalance(state, partial, 0n)).to.be.revertedWithCustomError(host, "InvalidBlock");
      }
    }
  });

  it("allocates exactly one balance per inner asset amount", async () => {
    for (const count of [0, 1, 2, 4, 8, 16, 32]) {
      const input = encodeBootstrapBlock(3n, concat(...Array(count).fill(encodeAssetAmountBlock(asset, 100n))));
      const expected = concat(...Array(count).fill(balance));
      for (const result of [
        await host.measureBootstrap.staticCall("0x", input, 7n),
        await host.measureBoth.staticCall(input, concat(...Array(count).fill(limits)), 7n),
      ]) {
        expect(Array.from(result).slice(1)).to.deep.equal([true, expected, 7n]);
        expect(ethers.dataLength(result[2])).to.equal(count * 72);
      }
    }
  });

  it("rejects bootstrap state, truncation, and incorrect headers without debiting", async () => {
    await expect(host.measureBootstrap(balance, bootstrap, 0n)).to.be.revertedWithCustomError(host, "UnexpectedState");
    for (const size of [1, 7, 8, 9, 39, 40, 71, 72, 103]) {
      await expect(host.measureBootstrap("0x", ethers.dataSlice(bootstrap, 0, size), 0n))
        .to.be.revertedWithCustomError(host, "InvalidBlock");
    }
    for (const bad of ["0xffffffff" + bootstrap.slice(10), bootstrap.slice(0, 10) + "00000000" + bootstrap.slice(18)]) {
      await expect(host.measureBootstrap("0x", bad, 0n)).to.be.revertedWithCustomError(host, "InvalidBlock");
    }
    expect(await host.balances(asset)).to.equal(10_000n);
    expect(await host.balances(native)).to.equal(10_000n);
  });

  it("uses assigned value for native amounts and debits only the remainder plus budget", async () => {
    const input = encodeBootstrapBlock(5n, encodeAssetAmountBlock(native, 7n));
    for (const value of [0n, 4n, 10n]) {
      await host.seed(native, 100n);
      const result = await host.measureBootstrap.staticCall("0x", input, value);
      expect(Array.from(result).slice(1)).to.deep.equal([true, encodeBalanceBlock(native, 7n), (value > 12n ? value - 7n : 5n)]);
      await (await host.measureBootstrap("0x", input, value)).wait();
      expect(await host.balances(native)).to.equal(100n - (value < 12n ? 12n - value : 0n));
    }
  });

  it("retains sufficient assigned budget and rolls back earlier debits on failure", async () => {
    await (await host.measureBoth(bootstrap, limits, 7n)).wait();
    expect(await host.balances(asset)).to.equal(9_900n);
    expect(await host.balances(native)).to.equal(10_000n);
    await expectOverflow(host.measureBootstrap("0x", encodeBootstrapBlock(3n, concat(encodeAssetAmountBlock(asset, 100n), encodeAssetAmountBlock(asset, 10_000n))), 0n, { gasLimit: 1_000_000 }));
    await expect(host.measureBoth(bootstrap, encodeBalanceConstraintsBlock(asset, 101n, 101n), 0n, { gasLimit: 1_000_000 }))
      .to.be.revertedWithCustomError(host, "OutOfRange");
    expect(await host.balances(asset)).to.equal(9_900n);
    expect(await host.balances(native)).to.equal(10_000n);
  });

  it("checks aggregate debit overflow without overflowing excess assigned credit", async () => {
    await host.seed(native, ethers.MaxUint256);
    for (const [input, value] of [
      [encodeBootstrapBlock(1n, encodeAssetAmountBlock(native, ethers.MaxUint256)), 0n],
    ] as const) {
      await expectOverflow(host.measureBootstrap("0x", input, value, { gasLimit: 1_000_000 }));
    }
    expect((await host.measureBootstrap.staticCall("0x", encodeBootstrapBlock(1n), ethers.MaxUint256))[3]).eq(ethers.MaxUint256);
    expect(await host.balances(asset)).to.equal(10_000n);
    expect(await host.balances(native)).to.equal(ethers.MaxUint256);
  });
});
