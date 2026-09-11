import { expect } from "chai";
import { ethers } from "ethers";
import { deploy } from "./helpers/setup.js";

describe("Fees", () => {
  let fees: Awaited<ReturnType<typeof deploy>>;

  before(async () => {
    fees = await deploy("TestFees");
  });

  it("returns the whole fee at inclusive limits and zero when it cannot fit", async () => {
    expect(await fees.deductible(10_000n, 250, 9_750n)).to.equal(250n);
    expect(await fees.deductible(10_000n, 250, 9_751n)).to.equal(0n);
    expect(await fees.addable(10_000n, 250, 10_250n)).to.equal(250n);
    expect(await fees.addable(10_000n, 250, 10_249n)).to.equal(0n);
  });

  it("selects addition or deduction from the signed rate and returns an unsigned fee", async () => {
    expect(await fees.calculate(10_000n, 250, 10_250n)).to.equal(250n);
    expect(await fees.calculate(10_000n, 250, 10_249n)).to.equal(0n);
    expect(await fees.calculate(10_000n, -250, 9_750n)).to.equal(250n);
    expect(await fees.calculate(10_000n, -250, 9_751n)).to.equal(0n);
    expect(await fees.calculate(10_000n, 250, 9_999n)).to.equal(0n);
    expect(await fees.calculate(10_000n, -250, 10_001n)).to.equal(0n);
    expect(await fees.calculate(10_000n, 0, 0n)).to.equal(0n);
    expect(await fees.calculate(10_000n, 0, ethers.MaxUint256)).to.equal(0n);
    expect(await fees.calculate(1n, -1, 0n)).to.equal(1n);
    expect(await fees.calculate(1n, 1, 2n)).to.equal(1n);
  });

  it("handles signed rate extremes, including int16 minimum without negation overflow", async () => {
    expect(await fees.calculate(10_000n, 32_767, 42_767n)).to.equal(32_767n);
    expect(await fees.calculate(1n, -32_768, 0n)).to.equal(0n);
    expect(await fees.calculate(0n, -32_768, 0n)).to.equal(0n);
    expect(await fees.calculate(ethers.MaxUint256, -32_768, 0n)).to.equal(0n);
    expect(await fees.calculate(ethers.MaxUint256, -10_000, 0n)).to.equal(ethers.MaxUint256);
  });

  it("returns zero for amounts already outside the limit", async () => {
    expect(await fees.deductible(100n, 100, 101n)).to.equal(0n);
    expect(await fees.addable(100n, 100, 99n)).to.equal(0n);
  });

  it("rounds up and permits zero amounts and rates", async () => {
    for (const method of ["deductible", "addable"]) {
      const limit = method === "deductible" ? 0n : ethers.MaxUint256;
      expect(await fees[method](0n, 250, limit)).to.equal(0n);
      expect(await fees[method](10_000n, 0, limit)).to.equal(0n);
      expect(await fees[method](1n, 1, limit)).to.equal(1n);
      expect(await fees[method](10_099n, 250, limit)).to.equal(253n);
    }
  });

  it("handles full deductions and surcharges above 100 percent", async () => {
    expect(await fees.deductible(100n, 10_000, 0n)).to.equal(100n);
    expect(await fees.deductible(100n, 20_000, 0n)).to.equal(0n);
    expect(await fees.addable(100n, 20_000, 300n)).to.equal(200n);
  });

  it("charges one unit through 400 at 25 bps and enforces the rounded limit", async () => {
    for (const amount of [1n, 399n, 400n, 401n]) {
      const fee = amount <= 400n ? 1n : 2n;
      expect(await fees.addable(amount, 25, amount + fee)).to.equal(fee);
      expect(await fees.addable(amount, 25, amount + fee - 1n)).to.equal(0n);
      expect(await fees.deductible(amount, 25, amount - fee)).to.equal(fee);
      expect(await fees.deductible(amount, 25, amount - fee + 1n)).to.equal(0n);
    }
  });

  it("matches arbitrary-precision arithmetic at uint boundaries without overflow", async () => {
    const max = ethers.MaxUint256;
    for (const amount of [max, max - 1n, max / 2n, max / 10n]) {
      for (const bps of [1n, 250n, 10_000n, 65_535n]) {
        const fee = (amount * bps + 9_999n) / 10_000n;
        expect(await fees.deductible(amount, bps, 0n)).to.equal(fee <= amount ? fee : 0n);
        expect(await fees.addable(amount, bps, max)).to.equal(fee <= max - amount ? fee : 0n);
        if (fee <= amount) {
          expect(await fees.deductible(amount, bps, amount - fee)).to.equal(fee);
        }
      }
    }
  });
});
