import { expect } from "chai";
import { ethers } from "ethers";
import { deploy } from "./helpers/setup.js";
import { concat, encodeBlock, encodeAmountBlock, encodeAssetAmountBlock, exactSpec, Keys } from "./helpers/blocks.js";
import "./helpers/matchers.js";

describe("Amount and AssetAmount blocks", () => {
  const asset = ethers.toBeHex(123, 32);

  it("publishes distinct scalar and asset-pair layouts", async () => {
    const helper = await deploy("TestAmountBlocks");
    for (const [method, alias, size, schema] of [
      ["layout", "amount", 32, "uint amount"],
      ["assetLayout", "assetAmount", 64, "bytes32 asset, uint amount"],
    ] as const) {
      const key = ethers.id(`#${alias}`).slice(0, 10);
      expect(Array.from(await helper[method]())).to.deep.equal([
        key, exactSpec(key, size), (BigInt(key) << 32n) | BigInt(size), BigInt(size + 8), schema,
      ]);
    }
  });

  it("round-trips zero and full-width values through creators, writers, execution, and fixed decoding", async () => {
    const helper = await deploy("TestAmountBlocks");
    for (const amount of [0n, 123n, ethers.MaxUint256]) {
      const scalar = encodeAmountBlock(amount);
      const pair = encodeAssetAmountBlock(asset, amount);
      for (const capacity of [0, 40, 72]) {
        expect(Array.from(await helper.encode(amount, capacity))).to.deep.equal([scalar, scalar, scalar]);
        expect(Array.from(await helper.encodeAsset(asset, amount, capacity))).to.deep.equal([pair, pair, pair, pair]);
      }
      for (const execution of [false, true]) {
        expect(Array.from(await helper.decode(concat(scalar, pair), 112, execution)))
          .to.deep.equal([amount, 40n, 72n]);
      }
      for (const mode of [0, 1, 2]) {
        expect(Array.from(await helper.decodeAsset(concat(pair, scalar), 112, mode)))
          .to.deep.equal([asset, amount, 40n]);
      }
      expect(Array.from(await helper.decodeFixed(scalar, false))).to.deep.equal([ethers.ZeroHash, amount]);
      expect(Array.from(await helper.decodeFixed(pair, true))).to.deep.equal([asset, amount]);
    }
  });

  it("rejects swapped keys, old amount pairs, wrong widths, and bounded truncation", async () => {
    const helper = await deploy("TestAmountBlocks");
    const scalar = encodeAmountBlock(1n);
    const pair = encodeAssetAmountBlock(asset, 1n);
    const oldPair = encodeBlock(Keys.Amount, concat(asset, ethers.toBeHex(1, 32)));
    for (const execution of [false, true]) {
      for (const source of [pair, oldPair, encodeBlock(Keys.Amount, "0x"),
        encodeBlock(Keys.Amount, "0x" + "00".repeat(31)), encodeBlock(Keys.Amount, "0x" + "00".repeat(33))]) {
        await expect(helper.decode(source, ethers.dataLength(source), execution))
          .to.be.revertedWithCustomError(helper, "InvalidBlock");
      }
      await expect(helper.decode(scalar, 39, execution)).to.be.revertedWithCustomError(helper, "OutOfBounds");
    }
    for (const mode of [0, 1, 2]) {
      for (const source of [scalar, oldPair, encodeBlock(Keys.AssetAmount, "0x" + "00".repeat(63)),
        encodeBlock(Keys.AssetAmount, "0x" + "00".repeat(65))]) {
        await expect(helper.decodeAsset(source, ethers.dataLength(source), mode))
          .to.be.revertedWithCustomError(helper, "InvalidBlock");
      }
      await expect(helper.decodeAsset(pair, 71, mode)).to.be.revertedWithCustomError(helper, "OutOfBounds");
    }
    await expect(helper.decodeFixed(oldPair, true)).to.be.revertedWithCustomError(helper, "InvalidBlock");
    await expect(helper.decodeFixed(encodeBlock(Keys.AssetAmount, ethers.toBeHex(1, 32)), false))
      .to.be.revertedWithCustomError(helper, "InvalidBlock");
  });
});
