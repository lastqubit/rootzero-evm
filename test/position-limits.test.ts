import { expect } from "chai";
import { ethers } from "ethers";
import { deploy } from "./helpers/setup.js";
import { encodeContextBlock, MaxUint128, packLimits, concat, encodeBlock, exactSpec, Keys, encodePositionBlock, encodePositionLimitsBlock, encodeUserAccount } from "./helpers/blocks.js";
import "./helpers/matchers.js";

describe("PositionLimits codec", () => {
  const asset = ethers.zeroPadValue("0x11", 32);
  const liability = ethers.zeroPadValue("0x22", 32);
  const counterparty = encodeUserAccount("0x0000000000000000000000000000000000000033");
  const positionLimits = [asset, 123n, liability, 456n];
  const encoded = encodePositionLimitsBlock(asset, 123n, liability, 456n);
  const state = encodePositionBlock(liability, 99n, asset, 77n);
  let helper: Awaited<ReturnType<typeof deploy>>;
  before(async () => { helper = await deploy("TestPositionLimits"); });

  it("advertises four full-width words in position field order", async () => {
    expect(Array.from(await helper.metadata())).to.deep.equal([
      exactSpec(Keys.PositionLimits, 128), 136n, "bytes32 asset, uint minAmount, bytes32 liability, uint maxDebt",
    ]);
    expect(ethers.dataLength(encoded)).to.equal(136);
    expect(ethers.dataSlice(encoded, 8)).to.equal(ethers.dataSlice(
      encodePositionBlock(asset, 123n, liability, 456n, counterparty), 8, 136,
    ));
  });

  for (const amount of [0n, 123n, MaxUint128, MaxUint128 + 1n, ethers.MaxUint256]) {
    it(`decodes full-width amount and debt ${amount}`, async () => {
      const debt = ethers.MaxUint256 - amount;
      const value = [asset, amount, liability, debt];
      const block = encodePositionLimitsBlock(asset, amount, liability, debt);
      expect(Array.from(await helper.decode(block))).to.deep.equal(value);
      expect(Array.from(await helper.execute(encodeContextBlock(ethers.ZeroHash, state, block))))
        .to.deep.equal([asset, ethers.toBeHex(amount, 32), liability, ethers.toBeHex(debt, 32)]);
    });
  }

  for (const method of ["checkDirect", "checkExecution"] as const) {
    describe(method, () => {
      async function check(block: string, position: readonly unknown[]) {
        if (method === "checkDirect") {
          // Exercise unaligned absolute reads and preservation of the entire position.
          return Array.from(await helper.checkDirect(concat("0xaabbcc", block, "0xff"), 3, position));
        }
        // Returning the following limits block proves exactly one limits block was consumed.
        return Array.from(await helper[method](concat(block, encoded), position));
      }

      it("accepts equality, better outcomes, zero limits, and full-width bounds", async () => {
        for (const [minimum, maximum, amount, debt] of [
          [0n, 0n, 0n, 0n], [0n, 0n, ethers.MaxUint256, 0n],
          [123n, 456n, 123n, 456n], [123n, 456n, 124n, 455n],
          [MaxUint128 + 1n, MaxUint128 + 2n, MaxUint128 + 1n, MaxUint128 + 2n],
          [ethers.MaxUint256, ethers.MaxUint256, ethers.MaxUint256, ethers.MaxUint256],
        ]) {
          for (const actual of [ethers.ZeroHash, counterparty]) {
            const position = [asset, amount, liability, debt, actual];
            expect(await check(encodePositionLimitsBlock(asset, minimum, liability, maximum), position))
              .to.deep.equal(method === "checkDirect" ? position : positionLimits);
          }
        }
      });

      it("rejects either identifier mismatch before quantity errors", async () => {
        for (const position of [
          [liability, 0n, liability, ethers.MaxUint256, counterparty],
          [asset, 0n, asset, ethers.MaxUint256, counterparty],
        ]) {
          await expect(check(encoded, position)).to.be.revertedWithCustomError(helper, "UnexpectedValue");
        }
      });

      it("enforces both full-width inclusive bounds without truncation", async () => {
        for (const [minimum, maximum, amount, debt] of [
          [123n, 456n, 122n, 456n], [123n, 456n, 123n, 457n],
          [0n, 0n, 0n, 1n],
          [MaxUint128 + 1n, ethers.MaxUint256, MaxUint128, 0n],
          [0n, MaxUint128 + 1n, 0n, MaxUint128 + 2n],
          [ethers.MaxUint256, ethers.MaxUint256, ethers.MaxUint256 - 1n, 0n],
          [0n, ethers.MaxUint256 - 1n, 0n, ethers.MaxUint256],
        ]) {
          await expect(check(encodePositionLimitsBlock(asset, minimum, liability, maximum),
            [asset, amount, liability, debt, counterparty]))
            .to.be.revertedWithCustomError(helper, "OutOfRange");
        }
      });

      it("validates the exact header before identifiers and quantities", async () => {
        for (const [key, length] of [[Keys.Quote, 128], [Keys.Bytes, 128], [Keys.PositionLimits, 127], [Keys.PositionLimits, 129], [Keys.PositionLimits, 96]] as const) {
          const malformed = concat(key, ethers.toBeHex(length, 4), ethers.dataSlice(encoded, 8));
          await expect(check(malformed, [liability, 0n, asset, ethers.MaxUint256, counterparty]))
            .to.be.revertedWithCustomError(helper, "InvalidBlock");
        }
      });
    });
  }

  it("execution bounds the entire POSITION_LIMITS block before checking values", async () => {
    for (const length of [0, 7, 8, 40, 103, 104, 135]) {
      await expect(helper.checkExecution(ethers.dataSlice(encoded, 0, length),
        [liability, 0n, asset, ethers.MaxUint256, counterparty]))
        .to.be.revertedWithCustomError(helper, "OutOfBounds");
    }
  });

  it("consumes position limits independently of state", async () => {
    const second = encodePositionLimitsBlock(liability, ethers.MaxUint256, asset, MaxUint128 + 1n);
    expect(Array.from(await helper.execute(encodeContextBlock(ethers.ZeroHash, concat(state, state), concat(encoded, second)))))
      .to.deep.equal([asset, ethers.toBeHex(123n, 32), liability, ethers.toBeHex(456n, 32),
        liability, ethers.toBeHex(ethers.MaxUint256, 32), asset, ethers.toBeHex(MaxUint128 + 1n, 32)]);
    expect(Array.from(await helper.execute(encodeContextBlock(ethers.ZeroHash, "0x", "0x")))).to.deep.equal([]);
  });

  it("rejects truncation and incorrect headers", async () => {
    await expect(helper.decode(ethers.dataSlice(encoded, 0, 135)))
      .to.be.revertedWithCustomError(helper, "OutOfBounds");
    await expect(helper.decode(state)).to.be.revertedWithCustomError(helper, "InvalidBlock");
    for (const payload of [
      concat(asset, liability, ethers.toBeHex(packLimits(123n, 456n), 32)),
      concat(asset, ethers.toBeHex(123n, 32), liability, ethers.toBeHex(456n, 32), counterparty),
    ]) {
      const malformed = concat(encodeBlock(Keys.PositionLimits, payload), encoded);
      await expect(helper.decode(malformed)).to.be.revertedWithCustomError(helper, "InvalidBlock");
      await expect(helper.execute(encodeContextBlock(ethers.ZeroHash, state, malformed)))
        .to.be.revertedWithCustomError(helper, "InvalidBlock");
    }
  });
});
