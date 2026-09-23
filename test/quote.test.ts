import { expect } from "chai";
import { ethers } from "ethers";
import { deploy } from "./helpers/setup.js";
import { encodeContextBlock, MaxUint128, packLimits, concat, encodeBlock, exactSpec, Keys, encodePositionBlock, encodeQuoteBlock, encodeUserAccount } from "./helpers/blocks.js";
import "./helpers/matchers.js";

describe("Quote codec", () => {
  const asset = ethers.zeroPadValue("0x11", 32);
  const liability = ethers.zeroPadValue("0x22", 32);
  const counterparty = encodeUserAccount("0x0000000000000000000000000000000000000033");
  const quote = [asset, liability, packLimits(123n, MaxUint128)];
  const encoded = encodeQuoteBlock(asset, liability, packLimits(123n, MaxUint128));
  const state = encodePositionBlock(liability, 99n, asset, 77n);
  let helper: Awaited<ReturnType<typeof deploy>>;

  before(async () => { helper = await deploy("TestQuote"); });

  it("advertises a three-word quote with packed limits", async () => {
    expect(Array.from(await helper.metadata())).to.deep.equal([
      exactSpec(Keys.Quote, 96), 104n, "bytes32 asset, bytes32 liability, uint limits",
    ]);
  });

  it("checks identifiers before quantity bounds", async () => {
    await expect(helper.check(concat(encoded, encoded), [liability, 0n, asset, ethers.MaxUint256, ethers.ZeroHash]))
      .to.be.revertedWithCustomError(helper, "UnexpectedValue");
  });

  it("accepts full-width asset output but treats the maximum debt lane as a literal cap", async () => {
    const input = concat(encodeQuoteBlock(asset, liability, ethers.MaxUint256), encoded);
    for (const amount of [MaxUint128, MaxUint128 + 1n, ethers.MaxUint256]) {
      expect(Array.from(await helper.check(input, [asset, amount, liability, MaxUint128, counterparty])))
        .to.deep.equal(quote);
    }
    for (const debt of [MaxUint128 + 1n, ethers.MaxUint256]) {
      await expect(helper.check(input, [asset, ethers.MaxUint256, liability, debt, counterparty]))
        .to.be.revertedWithCustomError(helper, "OutOfRange");
    }
  });

  it("preserves both packed lanes across scalar and structured paths", async () => {
    for (const limits of [0n, MaxUint128, MaxUint128 << 128n, ethers.MaxUint256]) {
      const value = [asset, liability, limits];
      const block = encodeQuoteBlock(asset, liability, limits);
      expect(await helper.create(value)).to.equal(block);
      for (const scalar of [true, false]) {
        expect(await helper.write(value, scalar)).to.equal(block);
        expect(Array.from(await helper.decode(block, scalar))).to.deep.equal(value);
        expect(await helper.execute(encodeContextBlock(ethers.ZeroHash, state, block), scalar)).to.equal(block);
      }
    }
  });

  it("checks inclusive limits, and advances exactly one quote", async () => {
    const first = encodeQuoteBlock(asset, liability, packLimits(123n, 456n));
    expect(Array.from(await helper.check(concat(first, encoded), [asset, 123n, liability, 456n, counterparty])))
      .to.deep.equal(quote);
  });

  for (const [position, error] of [
    [[asset, 122n, liability, 456n, ethers.ZeroHash], "OutOfRange"],
    [[asset, 123n, liability, 457n, ethers.ZeroHash], "OutOfRange"],
    [[liability, 123n, liability, 456n, ethers.ZeroHash], "UnexpectedValue"],
    [[asset, 123n, asset, 456n, ethers.ZeroHash], "UnexpectedValue"],
  ] as const) {
    it(`rejects a result outside its quote: ${position.join(",")}`, async () => {
      await expect(helper.check(concat(encodeQuoteBlock(asset, liability, packLimits(123n, 456n)), encoded), position))
        .to.be.revertedWithCustomError(helper, error);
    });
  }

  for (const actual of [ethers.ZeroHash, counterparty, encodeUserAccount("0x0000000000000000000000000000000000000044")]) {
    it(`accepts a matching economic result independently of counterparty ${actual}`, async () => {
      const input = concat(encodeQuoteBlock(asset, liability, packLimits(123n, 456n)), encoded);
      expect(Array.from(await helper.check(input, [asset, 123n, liability, 456n, actual])))
        .to.deep.equal(quote);
    });
  }

  it("encodes three words with identifiers and packed limits", async () => {
    expect(ethers.dataLength(encoded)).to.equal(104);
    expect(await helper.create(quote)).to.equal(encoded);
  });

  for (const scalar of [true, false]) {
    it(`roundtrips ${scalar ? "scalar" : "struct"} writer and decoder fields`, async () => {
      expect(await helper.write(quote, scalar)).to.equal(encoded);
      expect(Array.from(await helper.decode(encoded, scalar))).to.deep.equal(quote);
    });

    it(`consumes quotes from input independently of position state (${scalar})`, async () => {
      const second = encodeQuoteBlock(liability, asset, packLimits(0n, 0n));
      expect(await helper.execute(encodeContextBlock(ethers.ZeroHash, concat(state, state), concat(encoded, second)), scalar))
        .to.equal(concat(encoded, second));
    });

    it(`rejects truncated quotes (${scalar})`, async () => {
      await expect(helper.decode(ethers.dataSlice(encoded, 0, 103), scalar))
        .to.be.revertedWithCustomError(helper, "OutOfBounds");
    });

    it(`rejects a position in place of a quote (${scalar})`, async () => {
      await expect(helper.decode(state, scalar)).to.be.revertedWithCustomError(helper, "InvalidBlock");
    });

    it(`rejects the quote key with an incorrect payload length (${scalar})`, async () => {
      const malformed = concat(ethers.dataSlice(encoded, 0, 4), ethers.toBeHex(160, 4), ethers.dataSlice(encoded, 8));
      await expect(helper.decode(malformed, scalar)).to.be.revertedWithCustomError(helper, "InvalidBlock");
    });

    it(`rejects the previous four-word quote (${scalar})`, async () => {
      const previous = encodeBlock(Keys.Quote, ethers.concat([
        asset, liability, counterparty, ethers.toBeHex(packLimits(123n, 456n), 32),
      ]));
      await expect(helper.decode(previous, scalar)).to.be.revertedWithCustomError(helper, "InvalidBlock");
      await expect(helper.execute(encodeContextBlock(ethers.ZeroHash, state, previous), scalar)).to.be.revertedWithCustomError(helper, "InvalidBlock");
    });

    it(`rejects the legacy five-word quote (${scalar})`, async () => {
      const legacy = encodeBlock(Keys.Quote, ethers.concat([
        asset, ethers.toBeHex(123n, 32), liability, ethers.toBeHex(456n, 32), counterparty,
      ]));
      await expect(helper.decode(legacy, scalar)).to.be.revertedWithCustomError(helper, "InvalidBlock");
      await expect(helper.execute(encodeContextBlock(ethers.ZeroHash, state, legacy), scalar)).to.be.revertedWithCustomError(helper, "InvalidBlock");
    });
  }
});
