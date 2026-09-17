import { expect } from "chai";
import { ethers } from "ethers";
import { deploy } from "./helpers/setup.js";
import { concat, encodeBalanceBlock } from "./helpers/blocks.js";
import "./helpers/matchers.js";

describe("Executions.scaleOutput", () => {
  let helper: any;
  before(async () => { helper = await deploy("TestScaleOutput"); });
  const max = (1n << 32n) - 1n;
  const flags = 0xabcdefn << 64n;
  for (const [capacity, numerator, denominator, expected] of [
    [72n, 3n, 1n, 216n], [144n, 1n, 2n, 72n], [145n, 3n, 2n, 217n],
    [72n, 0n, 1n, 0n], [0n, ethers.MaxUint256, 1n, 0n],
    [max, 2n, 2n, max], [1n, ethers.MaxUint256, ethers.MaxUint256, 1n],
    [72n, 1n, 1n, 72n],
  ]) {
    it(`scales ${capacity} by ${numerator}/${denominator} without allocation`, async () => {
      expect(await helper.scale(flags | (capacity << 32n), numerator, denominator)).to.equal(flags | (expected << 32n));
      expect(Array.from(await helper.inspect(flags | (capacity << 32n), numerator, denominator, 0)))
        .to.deep.equal([flags | (expected << 32n), 0n, 0n]);
    });
  }
  it("rejects a zero denominator even for an empty hint", async () => {
    for (const capacity of [0n, 72n]) {
      await expect(helper.scale(capacity << 32n, 1, 0)).to.be.revertedWithCustomError(helper, "ZeroAmount");
      await expect(helper.inspect(capacity << 32n, 1, 0, 0)).to.be.revertedWithCustomError(helper, "ZeroAmount");
    }
  });
  it("rejects capacity and intermediate-product overflow", async () => {
    for (const [capacity, numerator, denominator] of [[max, 2n, 1n], [2n, ethers.MaxUint256, ethers.MaxUint256]]) {
      await expect(helper.scale(capacity << 32n, numerator, denominator))
        .to.be.revertedWithCustomError(helper, "ValueOverflow");
      await expect(helper.inspect(capacity << 32n, numerator, denominator, 0))
        .to.be.revertedWithCustomError(helper, "ValueOverflow");
    }
  });
  it("rejects scaling after any reservation, including a zero-byte reservation", async () => {
    for (const mode of [1, 2]) {
      await expect(helper.inspect(72n << 32n, 2, 1, mode)).to.be.revertedWithCustomError(helper, "UnexpectedPosition");
    }
    await expect(helper.scale((72n << 32n) | 1n, 2, 1)).to.be.revertedWithCustomError(helper, "UnexpectedPosition");
    await expect(helper.inspect((72n << 32n) | 1n, 2, 1, 0)).to.be.revertedWithCustomError(helper, "UnexpectedPosition");
  });
  it("preserves output and grows beyond reduced or cleared hints", async () => {
    const expected = concat(...Array.from({ length: 3 }, (_, i) => encodeBalanceBlock(ethers.toBeHex(1, 32), BigInt(i + 1))));
    for (const [n, d] of [[3, 1], [1, 2], [0, 1]]) {
      const result = await helper.write(72, n, d, 3, true);
      expect(result[0]).to.equal(expected);
    }
  });
});
