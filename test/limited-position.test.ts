import { expect } from "chai";
import { ethers } from "ethers";
import { deploy } from "./helpers/setup.js";
import { MaxUint128, concat, encodeLimitsBlock, encodePositionBlock } from "./helpers/blocks.js";
import "./helpers/matchers.js";

for (const method of ["unpack", "unpackMemory"] as const) {
describe(`${method === "unpack" ? "Blocks" : "Memory"}.unpackLimitedPosition`, () => {
  // Opaque identifiers must be preserved, without account or asset checks.
  const asset = ethers.toBeHex(11n, 32);
  const liability = ethers.toBeHex(22n, 32);
  const counterparty = ethers.toBeHex(33n, 32);
  let helper: Awaited<ReturnType<typeof deploy>>;
  before(async () => { helper = await deploy("TestLimitedPosition"); });
  const position = (amount: bigint, debt: bigint) => encodePositionBlock(asset, amount, liability, debt, counterparty);

  if (method === "unpackMemory") it("returns independent copies without aliasing the source or each other", async () => {
    const [first, second, source] = await helper.copyIndependence(position(100n, 40n), encodeLimitsBlock(100n, 40n));
    expect(Array.from(first)).to.deep.equal([ethers.toBeHex(1n, 32), 2n, ethers.toBeHex(3n, 32), 4n, ethers.toBeHex(5n, 32)]);
    expect(Array.from(second)).to.deep.equal([asset, 100n, liability, 40n, counterparty]);
    expect(source).to.equal(position(999n, 40n));
  });

  for (const [amount, debt, minimum, maximum] of [
    [0n, 0n, 0n, 0n], [100n, 40n, 100n, 40n], [100n, 40n, 99n, 41n],
    [MaxUint128, MaxUint128, MaxUint128, MaxUint128],
    [MaxUint128 + 1n, MaxUint128, MaxUint128, MaxUint128],
    [ethers.MaxUint256, 0n, MaxUint128, 0n],
  ]) {
    it(`returns all five position fields within ${minimum}/${maximum} bounds`, async () => {
      expect(Array.from(await helper[method](position(amount, debt), 0, encodeLimitsBlock(minimum, maximum), 0)))
        .to.deep.equal([asset, amount, liability, debt, counterparty]);
    });
  }

  for (const [amount, debt, minimum, maximum] of [
    [99n, 40n, 100n, 40n], [100n, 41n, 100n, 40n], [99n, 41n, 100n, 40n],
    [0n, 1n, 0n, 0n], [MaxUint128 - 1n, 0n, MaxUint128, MaxUint128],
    [ethers.MaxUint256, MaxUint128 + 1n, 0n, MaxUint128],
    [ethers.MaxUint256, ethers.MaxUint256, 0n, MaxUint128],
  ]) {
    it(`rejects ${amount}/${debt} outside ${minimum}/${maximum} bounds without truncation`, async () => {
      await expect(helper[method](position(amount, debt), 0, encodeLimitsBlock(minimum, maximum), 0))
        .to.be.revertedWithCustomError(helper, "OutOfRange");
    });
  }

  it("reads independent, unaligned offsets without including adjacent blocks", async () => {
    const state = concat("0xabcdef", position(1n, 2n), position(100n, 40n), position(3n, 4n));
    const input = concat("0x1234567890", encodeLimitsBlock(0n, 0n), encodeLimitsBlock(100n, 40n), encodeLimitsBlock(0n, 0n));
    expect(Array.from(await helper[method](state, 3 + 168, input, 5 + 40)))
      .to.deep.equal([asset, 100n, liability, 40n, counterparty]);
  });

  for (const side of ["position", "limits"]) {
    for (const field of ["key", "length"]) {
      it(`rejects an invalid ${side} ${field} before quantity bounds`, async () => {
        let state = position(0n, ethers.MaxUint256);
        let input = encodeLimitsBlock(100n, 40n);
        const corrupt = (block: string) => field === "key"
          ? "0xffffffff" + block.slice(10)
          : block.slice(0, 10) + "00000000" + block.slice(18);
        if (side === "position") state = corrupt(state);
        else input = corrupt(input);
        await expect(helper[method](state, 0, input, 0)).to.be.revertedWithCustomError(helper, "InvalidBlock");
      });
    }
  }

  it("has its caller reject incomplete blocks and overflowing offsets", async () => {
    const state = position(100n, 40n);
    const input = encodeLimitsBlock(100n, 40n);
    for (const args of [
      [ethers.dataSlice(state, 0, 167), 0, input, 0],
      [state, 0, ethers.dataSlice(input, 0, 39), 0],
      [state, 1, input, 0], [state, 0, input, 1],
      [state, ethers.MaxUint256, input, 0], [state, 0, input, ethers.MaxUint256],
    ]) await expect(helper[method](...args)).to.be.revertedWithCustomError(helper, "OutOfBounds");
  });
});

}
