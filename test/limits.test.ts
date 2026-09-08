import { expect } from "chai";
import { ethers } from "ethers";
import { deploy } from "./helpers/setup.js";
import { concat, encodeLimitsBlock, encodeAmountBlock, exactSpec, Keys } from "./helpers/blocks.js";
import "./helpers/matchers.js";

describe("Limits codec", () => {
  let helper: Awaited<ReturnType<typeof deploy>>;
  before(async () => { helper = await deploy("TestLimits"); });

  it("advertises exactly two uint words", async () => {
    expect(Array.from(await helper.metadata())).to.deep.equal([
      exactSpec(Keys.Limits, 64), 72n, "uint amount, uint debt",
    ]);
  });

  for (const [amount, debt] of [[0n, 0n], [123n, 456n], [ethers.MaxUint256, 0n], [0n, ethers.MaxUint256]]) {
    it(`preserves amount ${amount} and debt ${debt}`, async () => {
      const encoded = encodeLimitsBlock(amount, debt);
      expect(ethers.dataLength(encoded)).to.equal(72);
      expect(await helper.create(amount, debt)).to.equal(encoded);
      expect(await helper.write([amount, debt])).to.equal(encoded);
      expect(Array.from(await helper.decode(encoded))).to.deep.equal([amount, debt]);
    });
  }

  it("roundtrips structured limits through cursor, memory, writer and execution helpers", async () => {
    const input = concat(encodeLimitsBlock(123n, 456n), encodeLimitsBlock(0n, ethers.MaxUint256));
    for (const mode of [0, 1, 2]) expect(await helper.structured(input, mode)).to.equal(input);
  });

  for (const execution of [false, true]) {
    describe(execution ? "execution requireLimits" : "cursor requireLimits", () => {
      const next = encodeLimitsBlock(77n, 88n);
      for (const [minimum, maximum, amount, debt] of [
        [10n, 20n, 10n, 20n], [10n, 20n, 11n, 19n],
        [0n, 0n, 0n, 0n], [ethers.MaxUint256, ethers.MaxUint256, ethers.MaxUint256, ethers.MaxUint256],
      ]) {
        it(`accepts inclusive bounds and advances one block (${amount}, ${debt})`, async () => {
          expect(Array.from(await helper.check(concat(encodeLimitsBlock(minimum, maximum), next), amount, debt, execution)))
            .to.deep.equal([77n, 88n]);
        });
      }
      for (const [amount, debt] of [[9n, 20n], [10n, 21n], [9n, 21n], [0n, ethers.MaxUint256]]) {
        it(`rejects quantities outside the limits (${amount}, ${debt})`, async () => {
          await expect(helper.check(concat(encodeLimitsBlock(10n, 20n), next), amount, debt, execution))
            .to.be.revertedWithCustomError(helper, "AmountOutOfRange");
        });
      }
      it("validates the header before quantity bounds", async () => {
        for (const invalid of [encodeAmountBlock(ethers.toBeHex(ethers.MaxUint256, 32), 0n),
          encodeLimitsBlock(10n, 20n).slice(0, 10) + "00000020" + encodeLimitsBlock(10n, 20n).slice(18)]) {
          await expect(helper.check(concat(invalid, next), 0n, ethers.MaxUint256, execution))
            .to.be.revertedWithCustomError(helper, "InvalidBlock");
        }
      });
      it("rejects empty and truncated input", async () => {
        for (const input of ["0x", ethers.dataSlice(encodeLimitsBlock(10n, 20n), 0, 71)]) {
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
      const encoded = concat(...Array.from({ length: 8 }, (_, i) => encodeLimitsBlock(BigInt(i), ethers.MaxUint256 - BigInt(i))));
      expect(await run(encoded)).to.equal(encoded);
    });

    it(`${path} accepts an empty stream`, async () => { expect(await run("0x")).to.equal("0x"); });

    it(`${path} rejects another two-word schema`, async () => {
      await expect(run(encodeAmountBlock(ethers.ZeroHash, 1n)))
        .to.be.revertedWithCustomError(helper, "InvalidBlock");
    });

    it(`${path} rejects the wrong payload length`, async () => {
      const encoded = encodeLimitsBlock(1n, 2n);
      await expect(run(encoded.slice(0, 10) + "00000020" + encoded.slice(18)))
        .to.be.revertedWithCustomError(helper, "InvalidBlock");
    });

    it(`${path} rejects a truncated second block`, async () => {
      const encoded = encodeLimitsBlock(1n, 2n);
      await expect(run(concat(encoded, ethers.dataSlice(encoded, 0, 71))))
        .to.be.revertedWithCustomError(helper, path === "memory" ? "InvalidBlock" : "OutOfBounds");
    });
  }
});
