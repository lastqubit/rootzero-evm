import { expect } from "chai";
import { ethers } from "ethers";
import { deploy } from "./helpers/setup.js";
import { concat, encodeAssetLimitsBlock, encodeBlock, Keys, exactSpec } from "./helpers/blocks.js";
import "./helpers/matchers.js";

describe("AssetLimits codec", () => {
  let helper: any;
  const asset = ethers.toBeHex(123n, 32);
  before(async () => { helper = await deploy("TestAssetLimits"); });

  it("advertises three full-width words and decodes their exact order", async () => {
    expect(Array.from(await helper.metadata())).to.deep.equal([
      exactSpec(Keys.AssetLimits, 96), 104n, "bytes32 asset, uint min, uint max",
    ]);
    expect(Array.from(await helper.decode(encodeAssetLimitsBlock(asset, 1n << 200n, ethers.MaxUint256), 0), lane => Array.from(lane as any)))
      .to.deep.equal([[asset], [1n << 200n], [ethers.MaxUint256]]);
  });

  for (const execution of [false, true]) describe(execution ? "execution expectation" : "direct expectation", () => {
    const next = encodeAssetLimitsBlock(ethers.ZeroHash, 7n, 9n);
    const run = (input: string, amount: bigint, expectedAsset = asset) =>
      helper.expectInput(concat(input, next), expectedAsset, amount, execution);

    it("checks full-width inclusive bounds and consumes exactly one input block", async () => {
      for (const amount of [0n, 1n, 1n << 200n, ethers.MaxUint256]) {
        expect(Array.from(await run(encodeAssetLimitsBlock(asset, amount, amount), amount)))
          .to.deep.equal([ethers.ZeroHash, 7n, 9n]);
      }
    });

    it("rejects header, identifier, and bound errors in order", async () => {
      const input = encodeAssetLimitsBlock(asset, 10n, 20n);
      await expect(run("0xffffffff" + input.slice(10), 0n, ethers.ZeroHash))
        .to.be.revertedWithCustomError(helper, "InvalidBlock");
      await expect(run(input, 0n, ethers.ZeroHash)).to.be.revertedWithCustomError(helper, "UnexpectedValue");
      for (const amount of [9n, 21n, ethers.MaxUint256]) {
        await expect(run(input, amount)).to.be.revertedWithCustomError(helper, "OutOfRange");
      }
      await expect(run(encodeAssetLimitsBlock(asset, 20n, 10n), 15n))
        .to.be.revertedWithCustomError(helper, "OutOfRange");
    });

    if (execution) it("bounds the complete block before comparing values", async () => {
      const input = encodeAssetLimitsBlock(asset, 10n, 20n);
      for (const length of [0, 7, 8, 40, 72, 103]) {
        await expect(helper.expectInput(ethers.dataSlice(input, 0, length), ethers.ZeroHash, 0n, true))
          .to.be.revertedWithCustomError(helper, "OutOfBounds");
      }
    });
  });

  for (const mode of [0, 1, 2]) describe(["cursor", "memory", "execution"][mode], () => {
    it("decodes full-width and inverted bounds without validation across a batch", async () => {
      const blocks = Array.from({ length: 8 }, (_, i) => encodeAssetLimitsBlock(
        ethers.toBeHex(i, 32), ethers.MaxUint256 - BigInt(i), BigInt(i)));
      const input = concat(...blocks);
      const [assets, mins, maxs] = await helper.decode(input, mode);
      expect(Array.from(assets)).to.deep.equal(Array.from({ length: 8 }, (_, i) => ethers.toBeHex(i, 32)));
      expect(Array.from(mins)).to.deep.equal(Array.from({ length: 8 }, (_, i) => ethers.MaxUint256 - BigInt(i)));
      expect(Array.from(maxs)).to.deep.equal(Array.from({ length: 8 }, (_, i) => BigInt(i)));
      expect(Array.from(await helper.decode("0x", mode), lane => Array.from(lane as any))).to.deep.equal([[], [], []]);
    });

    it("rejects wrong keys and sizes", async () => {
      const encoded = encodeAssetLimitsBlock(asset, 1n, 2n);
      for (const invalid of [
        "0xffffffff" + encoded.slice(10), encoded.slice(0, 10) + "00000080" + encoded.slice(18),
        encodeBlock(Keys.Limits, ethers.dataSlice(encoded, 8)),
      ]) await expect(helper.decode(invalid, mode)).to.be.revertedWithCustomError(helper, "InvalidBlock");
    });

    it("rejects a truncated final block", async () => {
      const encoded = encodeAssetLimitsBlock(asset, 1n, 2n);
      await expect(helper.decode(concat(encoded, encoded.slice(0, -2)), mode))
        .to.be.revertedWithCustomError(helper, mode === 1 ? "InvalidBlock" : "OutOfBounds");
    });
  });
});
