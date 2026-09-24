import { expect } from "chai";
import { ethers } from "ethers";
import { deploy } from "./helpers/setup.js";
import { MaxUint128, packLimits, concat, encodeBlock, encodeLimitsBlock, encodeAmountBlock, exactSpec, Keys } from "./helpers/blocks.js";
import "./helpers/matchers.js";

describe("Limits codec", () => {
  let helper: Awaited<ReturnType<typeof deploy>>;
  before(async () => { helper = await deploy("TestLimits"); });

  it("advertises one packed uint word", async () => {
    expect(Array.from(await helper.metadata())).to.deep.equal([
      exactSpec(Keys.Limits, 32), 40n, "uint limits",
    ]);
  });

  for (const [amount, debt] of [[0n, 0n], [123n, 456n], [MaxUint128, 0n], [0n, MaxUint128], [MaxUint128, MaxUint128]]) {
    it(`preserves amount ${amount} and debt ${debt}`, async () => {
      const encoded = encodeLimitsBlock(amount, debt);
      expect(ethers.dataLength(encoded)).to.equal(40);
      expect(await helper.create(packLimits(amount, debt))).to.equal(encoded);
      expect(await helper.write([packLimits(amount, debt)])).to.equal(encoded);
      expect(await helper.decode(encoded)).to.equal(packLimits(amount, debt));
    });
  }

  it("packs amount in the high lane and debt in the low lane", async () => {
    const packed = (123n << 128n) | 456n;
    const encoded = encodeBlock(Keys.Limits, ethers.toBeHex(packed, 32));
    expect(await helper.create(packed)).to.equal(encoded);
    expect(await helper.decode(encoded)).to.equal(packed);
  });

  it("treats the maximum debt lane as a literal cap without truncating position quantities", async () => {
    const check = (amount: bigint, debt: bigint) => helper.check(
      concat(encodeLimitsBlock(MaxUint128, MaxUint128), encodeLimitsBlock(0n, 0n)), amount, debt, true);
    for (const amount of [MaxUint128, MaxUint128 + 1n, ethers.MaxUint256]) {
      await check(amount, MaxUint128);
    }
    for (const debt of [MaxUint128 + 1n, 1n << 255n, ethers.MaxUint256]) {
      await expect(check(ethers.MaxUint256, debt))
        .to.be.revertedWithCustomError(helper, "OutOfRange");
    }
    await expect(check(MaxUint128 - 1n, 0n))
      .to.be.revertedWithCustomError(helper, "OutOfRange");
  });

  it("rejects out-of-range packing inputs", () => {
    for (const value of [-1n, MaxUint128 + 1n, ethers.MaxUint256]) {
      expect(() => packLimits(value, 0n)).to.throw(RangeError);
      expect(() => packLimits(0n, value)).to.throw(RangeError);
    }
  });

  for (const execution of [false, true]) {
    describe(execution ? "position limits from execution" : "position limits from cursor", () => {
      const next = encodeLimitsBlock(77n, 88n);
      for (const [minimum, maximum, amount, debt] of [
        [10n, 20n, 10n, 20n], [10n, 20n, 11n, 19n],
        [0n, 0n, 0n, 0n], [MaxUint128, MaxUint128, MaxUint128, MaxUint128],
      ]) {
        it(`accepts inclusive bounds and advances one block (${amount}, ${debt})`, async () => {
          expect(await helper.check(concat(encodeLimitsBlock(minimum, maximum), next), amount, debt, execution))
            .to.equal(packLimits(77n, 88n));
        });
      }
      for (const [amount, debt] of [[9n, 20n], [10n, 21n], [9n, 21n], [0n, MaxUint128]]) {
        it(`rejects quantities outside the limits (${amount}, ${debt})`, async () => {
          await expect(helper.check(concat(encodeLimitsBlock(10n, 20n), next), amount, debt, execution))
            .to.be.revertedWithCustomError(helper, "OutOfRange");
        });
      }
      it("validates the header before quantity bounds", async () => {
        for (const invalid of [encodeAmountBlock(ethers.toBeHex(MaxUint128, 32), 0n),
          encodeLimitsBlock(10n, 20n).slice(0, 10) + "00000040" + encodeLimitsBlock(10n, 20n).slice(18)]) {
          await expect(helper.check(concat(invalid, next), 0n, MaxUint128, execution))
            .to.be.revertedWithCustomError(helper, "InvalidBlock");
        }
      });
      it("rejects empty and truncated input", async () => {
        for (const input of ["0x", ethers.dataSlice(encodeLimitsBlock(10n, 20n), 0, 39)]) {
          await expect(helper.check(input, 10n, 20n, execution))
            .to.be.revertedWithCustomError(helper, "OutOfBounds");
        }
      });
    });
  }

  for (const path of ["calldata", "memory", "execution"]) {
    const run = (input: string) => path === "execution"
      ? helper.execute(input) : helper.roundtrip(input, path === "memory");

    it(`${path} advances through batches and grows output correctly`, async () => {
      const encoded = concat(...Array.from({ length: 8 }, (_, i) => encodeLimitsBlock(BigInt(i), MaxUint128 - BigInt(i))));
      expect(await run(encoded)).to.equal(encoded);
    });

    it(`${path} accepts an empty stream`, async () => { expect(await run("0x")).to.equal("0x"); });

    it(`${path} rejects another schema`, async () => {
      await expect(run(encodeAmountBlock(ethers.ZeroHash, 1n)))
        .to.be.revertedWithCustomError(helper, "InvalidBlock");
    });

    it(`${path} rejects the wrong payload length`, async () => {
      const encoded = encodeLimitsBlock(1n, 2n);
      await expect(run(encoded.slice(0, 10) + "00000040" + encoded.slice(18)))
        .to.be.revertedWithCustomError(helper, "InvalidBlock");
    });

    it(`${path} rejects the legacy two-word LIMITS encoding`, async () => {
      const legacy = encodeBlock(Keys.Limits, ethers.concat([ethers.toBeHex(1n, 32), ethers.toBeHex(2n, 32)]));
      await expect(run(legacy)).to.be.revertedWithCustomError(helper, "InvalidBlock");
    });

    it(`${path} rejects a truncated second block`, async () => {
      const encoded = encodeLimitsBlock(1n, 2n);
      await expect(run(concat(encoded, ethers.dataSlice(encoded, 0, 39))))
        .to.be.revertedWithCustomError(helper, path === "memory" ? "InvalidBlock" : "OutOfBounds");
    });
  }
});
