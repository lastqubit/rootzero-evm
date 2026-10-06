import { expect } from "chai";
import { ethers } from "ethers";
import { deploy } from "./helpers/setup.js";
import { concat, encodeBlock, encodeBootstrapBlock, encodeAssetAmountBlock, encodeBalanceBlock, Keys } from "./helpers/blocks.js";
import "./helpers/matchers.js";

const asset = ethers.id("bootstrap-asset");
const dataLogs = (receipt: any) => receipt.logs.filter((log: any) => !log.topics.length).map((log: any) => log.data);

async function expectRevert(call: Promise<unknown>) {
  let failed = false;
  try { await call; } catch { failed = true; }
  expect(failed, "expected a revert").eq(true);
}

describe("Bootstrap composite input", () => {
  it("round trips the budget and list through Encoder, Blocks, and Executions", async () => {
    const codec = await deploy("TestBootstrapCodec");
    expect(Array.from(await codec.catalog())).deep.eq([
      (BigInt(Keys.Bootstrap) << 224n) | (40n << 192n) | (256n << 136n),
      "uint budget, many #assetAmount as balances",
    ]);
    const valid = encodeBootstrapBlock(0n, encodeAssetAmountBlock(asset, 1n));
    for (const execution of [false, true]) {
      await expectRevert(codec.unpack(valid, ethers.dataLength(valid) - 1, execution));
      const badList = encodeBlock(Keys.Bootstrap, concat(ethers.toBeHex(0, 32), encodeBlock(Keys.List, "0x"), "0x01"));
      await expectRevert(codec.unpack(badList, ethers.dataLength(badList), execution));
    }
    for (const budget of [0n, 1n, ethers.MaxUint256]) {
      for (const balances of ["0x", encodeAssetAmountBlock(asset, ethers.MaxUint256)]) {
        const input = encodeBootstrapBlock(budget, balances);
        expect(await codec.create(budget, balances)).eq(input);
        for (const execution of [false, true]) {
          expect(Array.from(await codec.unpack(input, ethers.dataLength(input), execution)))
            .deep.eq([budget, balances, 0n, 0xa5n]);
          const extra = concat(input, encodeBalanceBlock(asset, 1n));
          expect(Array.from(await codec.unpack(extra, ethers.dataLength(extra), execution)))
            .deep.eq([budget, balances, 72n, 0xa5n]);
          expect(Array.from(await codec.unpack(extra, ethers.dataLength(input), execution)))
            .deep.eq([budget, balances, 0n, 0xa5n]);
        }
      }
    }
  });

  it("unpacks exactly one Bootstrap and rejects malformed framing with InvalidBlock", async () => {
    const codec = await deploy("TestBootstrapCodec");
    for (const balances of ["0x", encodeAssetAmountBlock(asset, ethers.MaxUint256)]) {
      const input = encodeBootstrapBlock(ethers.MaxUint256, balances);
      const size = ethers.dataLength(input);
      expect(Array.from(await codec.unpackExact(concat(input, "0xaabb"), size)))
        .deep.eq([ethers.MaxUint256, balances]);
      for (const length of [0, 1, 7, 8, 39, 40, size - 1]) {
        await expect(codec.unpackExact(input, length)).revertedWithCustomError(codec, "InvalidBlock");
      }
      for (const bad of [concat(input, "0x01"), concat(input, input),
        encodeBlock(Keys.Bytes, ethers.dataSlice(input, 8)),
        encodeBlock(Keys.Bootstrap, ethers.toBeHex(0, 32)),
        encodeBlock(Keys.Bootstrap, concat(ethers.toBeHex(0, 32), encodeBlock(Keys.Bytes, balances))),
        encodeBlock(Keys.Bootstrap, concat(ethers.toBeHex(0, 32), encodeBlock(Keys.List, balances), "0x01")),
      ]) await expect(codec.unpackExact(bad, ethers.dataLength(bad))).revertedWithCustomError(codec, "InvalidBlock");
    }
    // Exact framing does not interpret the list's contents; the command does that.
    const opaque = encodeBootstrapBlock(1n, "0xab");
    expect(Array.from(await codec.unpackExact(opaque, ethers.dataLength(opaque)))).deep.eq([1n, "0xab"]);
  });

  it("requires one outer block and a well-formed list of AssetAmount blocks", async () => {
    const host = await deploy("TestAdapterOptimizations");
    const empty = encodeBootstrapBlock(0n);
    for (const input of ["0x", concat(empty, empty), concat(empty, "0x01"),
      encodeBlock(Keys.Bootstrap, ethers.toBeHex(0, 32)),
      encodeBlock(Keys.Bootstrap, concat(ethers.toBeHex(0, 32), encodeBlock(Keys.Bytes, "0x"))),
      encodeBootstrapBlock(0n, "0x01"),
      encodeBootstrapBlock(0n, encodeBalanceBlock(asset, 1n)),
      encodeBootstrapBlock(0n, encodeBlock(Keys.AssetAmount, ethers.toBeHex(1, 32))),
    ]) await expectRevert(host.measureBootstrap("0x", input, 0n));
  });

  for (const value of [0n, 4n, 10n, 12n, 20n]) {
    it(`funds repeated chainAsset requests and calls one actual native debit with assigned value ${value}`, async () => {
      const host = await deploy("TestAdapterOptimizations");
      const native = await host.nativeAsset();
      await host.seed(native, 100n);
      await host.seed(asset, 100n);
      const balances = concat(encodeAssetAmountBlock(native, 3n), encodeAssetAmountBlock(asset, 2n), encodeAssetAmountBlock(native, 4n));
      const input = encodeBootstrapBlock(5n, balances);
      const output = concat(encodeBalanceBlock(native, 3n), encodeBalanceBlock(asset, 2n), encodeBalanceBlock(native, 4n));
      const credit = value > 12n ? value - 7n : 5n;
      const debit = value < 12n ? 12n - value : 0n;
      expect(Array.from(await host.measureBootstrap.staticCall("0x", input, value)).slice(1)).deep.eq([true, output, credit]);
      const receipt = await (await host.measureBootstrap("0x", input, value)).wait();
      expect(await host.balances(native)).eq(100n - debit);
      expect(await host.balances(asset)).eq(98n);
      const hooks = receipt.logs.filter((log: any) => log.topics.length).map((log: any) => host.interface.parseLog(log).args.toArray());
      expect(hooks).deep.eq(debit ? [[asset, 2n], [native, debit]] : [[asset, 2n]]);
      expect(dataLogs(receipt)).deep.eq([]);
    });
  }

  it("supports budget-only input and zero requests without zero-amount hooks", async () => {
    const host = await deploy("TestAdapterOptimizations");
    const native = await host.nativeAsset();
    await host.seed(native, 10n);
    const input = encodeBootstrapBlock(5n);
    expect(Array.from(await host.measureBootstrap.staticCall("0x", input, 2n)).slice(1)).deep.eq([true, "0x", 5n]);
    const funded = await (await host.measureBootstrap("0x", input, 2n)).wait();
    expect(dataLogs(funded)).deep.eq([]);
    expect(await host.balances(native)).eq(7n);
    const receipt = await (await host.measureBootstrap("0x", encodeBootstrapBlock(0n, encodeAssetAmountBlock(asset, 0n)), 0n)).wait();
    expect(receipt.logs.filter((log: any) => log.topics.length)).deep.eq([]);
    expect(dataLogs(receipt)).deep.eq([]);
  });

  it("checks the native request total and rolls back when the final debit fails", async () => {
    const host = await deploy("TestAdapterOptimizations");
    const native = await host.nativeAsset();
    await host.seed(native, ethers.MaxUint256);
    const twice = encodeBootstrapBlock(0n, concat(...Array(2).fill(encodeAssetAmountBlock(native, ethers.MaxUint256))));
    // The requested total must fit even when assigned value would cover the excess.
    await expectRevert(host.measureBootstrap.staticCall("0x", twice, ethers.MaxUint256));
    const maximum = encodeBootstrapBlock(0n, encodeAssetAmountBlock(native, ethers.MaxUint256));
    expect((await host.measureBootstrap.staticCall("0x", maximum, ethers.MaxUint256))[3]).eq(0n);
    // Budget need not fit when added to requests; only requests and actual debit must fit.
    const maximumBudget = encodeBootstrapBlock(ethers.MaxUint256, encodeAssetAmountBlock(native, ethers.MaxUint256));
    expect((await host.measureBootstrap.staticCall("0x", maximumBudget, ethers.MaxUint256))[3]).eq(ethers.MaxUint256);
    await expectRevert(host.measureBootstrap("0x", twice, 0n));
    await host.seed(native, 0n);
    await host.seed(asset, 10n);
    await expectRevert(host.measureBootstrap("0x", encodeBootstrapBlock(1n, encodeAssetAmountBlock(asset, 4n)), 0n));
    expect(await host.balances(asset)).eq(10n);
  });

  it("preserves output across native requests, zero amounts, and allocating hooks", async () => {
    const host = await deploy("ExecuteOutputCurrent");
    await host.setAllocate(true);
    const native = await host.nativeAsset();
    for (const requests of [
      [[asset, 3n]], [[native, 3n]], [[asset, 0n]],
      [[native, 3n], [asset, 2n]], [[asset, 2n], [native, 3n]],
      [[asset, 0n], [asset, 2n]], [[asset, 2n], [asset, 0n]],
    ] as [string, bigint][][]) {
      for (const value of [0n, 10n]) {
        const input = encodeBootstrapBlock(0n, concat(...requests.map(([a, n]) => encodeAssetAmountBlock(a, n))));
        const output = concat(...requests.map(([a, n]) => encodeBalanceBlock(a, n)));
        expect((await host.measureBootstrap.staticCall("0x", input, value))[2]).eq(output);
        const receipt = await (await host.measureBootstrap("0x", input, value)).wait();
        expect(dataLogs(receipt)).deep.eq([]);
      }
    }
  });

  it("reserves complete output before hooks allocate memory", async () => {
    const host = await deploy("ExecuteOutputCurrent");
    await host.setAllocate(true);
    for (const count of [0, 1, 2, 8, 32]) {
      const input = encodeBootstrapBlock(2n, concat(...Array(count).fill(encodeAssetAmountBlock(asset, 3n))));
      const result = await host.measureBootstrap.staticCall("0x", input, 0n);
      expect(result[2]).eq(concat(...Array(count).fill(encodeBalanceBlock(asset, 3n))));
      expect(result[3]).eq(2n);
    }
  });
});
