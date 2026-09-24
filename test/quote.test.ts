import { expect } from "chai";
import { ethers } from "ethers";
import { deploy } from "./helpers/setup.js";
import { encodeContextBlock, MaxUint128, packLimits, concat, encodeBlock, exactSpec, Keys, encodePositionBlock, encodeQuoteBlock, encodeUserAccount } from "./helpers/blocks.js";
import "./helpers/matchers.js";

describe("Quote codec", () => {
  const asset = ethers.zeroPadValue("0x11", 32);
  const liability = ethers.zeroPadValue("0x22", 32);
  const counterparty = encodeUserAccount("0x0000000000000000000000000000000000000033");
  const quote = [asset, 123n, liability, 456n];
  const encoded = encodeQuoteBlock(asset, 123n, liability, 456n);
  const state = encodePositionBlock(liability, 99n, asset, 77n);
  let helper: Awaited<ReturnType<typeof deploy>>;
  before(async () => { helper = await deploy("TestQuote"); });

  it("keeps QUOTE distinct from POSITION_LIMITS despite their matching payload size", async () => {
    const limits = concat(Keys.PositionLimits, ethers.toBeHex(128, 4), ethers.dataSlice(encoded, 8));
    await expect(helper.decode(limits, false)).to.be.revertedWithCustomError(helper, "InvalidBlock");
  });

  it("advertises four full-width words in position field order", async () => {
    expect(Array.from(await helper.metadata())).to.deep.equal([
      exactSpec(Keys.Quote, 128), 136n, "bytes32 asset, uint amount, bytes32 liability, uint debt",
    ]);
    expect(ethers.dataLength(encoded)).to.equal(136);
    expect(ethers.dataSlice(encoded, 8)).to.equal(ethers.dataSlice(
      encodePositionBlock(asset, 123n, liability, 456n, counterparty), 8, 136,
    ));
  });

  for (const amount of [0n, 123n, MaxUint128, MaxUint128 + 1n, ethers.MaxUint256]) {
    it(`round-trips full-width amount and debt ${amount}`, async () => {
      const debt = ethers.MaxUint256 - amount;
      const value = [asset, amount, liability, debt];
      const block = encodeQuoteBlock(asset, amount, liability, debt);
      expect(await helper.create(value)).to.equal(block);
      for (const scalar of [true, false]) {
        expect(await helper.write(value, scalar)).to.equal(block);
        expect(Array.from(await helper.decode(block, scalar))).to.deep.equal(value);
        expect(await helper.execute(encodeContextBlock(ethers.ZeroHash, state, block), scalar)).to.equal(block);
      }
    });
  }

  for (const scalar of [true, false]) {
    it(`consumes quotes independently of state (${scalar})`, async () => {
      const second = encodeQuoteBlock(liability, ethers.MaxUint256, asset, MaxUint128 + 1n);
      expect(await helper.execute(encodeContextBlock(ethers.ZeroHash, concat(state, state), concat(encoded, second)), scalar))
        .to.equal(concat(encoded, second));
    });

    it(`rejects truncation and incorrect headers (${scalar})`, async () => {
      await expect(helper.decode(ethers.dataSlice(encoded, 0, 135), scalar))
        .to.be.revertedWithCustomError(helper, "OutOfBounds");
      await expect(helper.decode(state, scalar)).to.be.revertedWithCustomError(helper, "InvalidBlock");
      for (const payload of [
        concat(asset, liability, ethers.toBeHex(packLimits(123n, 456n), 32)),
        concat(asset, ethers.toBeHex(123n, 32), liability, ethers.toBeHex(456n, 32), counterparty),
      ]) {
        // Trailing data makes the old short format readable; its header must still fail.
        const malformed = concat(encodeBlock(Keys.Quote, payload), encoded);
        await expect(helper.decode(malformed, scalar)).to.be.revertedWithCustomError(helper, "InvalidBlock");
        await expect(helper.execute(encodeContextBlock(ethers.ZeroHash, state, malformed), scalar))
          .to.be.revertedWithCustomError(helper, "InvalidBlock");
      }
    });
  }
});
