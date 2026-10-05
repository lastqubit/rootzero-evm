import { expect } from "chai";
import { ethers } from "ethers";
import { deploy } from "./helpers/setup.js";
import { encodeBalanceBlock } from "./helpers/blocks.js";
import "./helpers/matchers.js";

describe("Optimized credit return", () => {
  it("preserves empty output, full-width values, input metadata and source memory", async () => {
    const helper = await deploy("CreditCurrent");
    const block = encodeBalanceBlock(ethers.toBeHex(ethers.MaxUint256, 32), ethers.MaxUint256 - 1n);
    for (const state of ["0x", block, ethers.concat([block, block, block])]) {
      for (const cur of [0n, 9n | (9n << 32n) | (((1n << 192n) - 1n) << 64n)]) {
        const result = await helper.measure.staticCall(state, cur, ethers.MaxUint256);
        expect(result.handled).eq(true);
        expect(result.output).eq("0x");
        expect(result.credit).eq(ethers.MaxUint256);
        expect(result.stateHash).eq(ethers.keccak256(state));
      }
    }
  });

  it("retains input, framing and hook failures", async () => {
    const helper = await deploy("CreditCurrent");
    await expect(helper.measure("0x01", 1n << 32n, 0)).revertedWithCustomError(helper, "UnexpectedInput");
    await expect(helper.measure("0x01", 0, 0)).revertedWithCustomError(helper, "InvalidBlock");
    const badHeader = "0x" + "00".repeat(72);
    await expect(helper.measure(badHeader, 0, 0)).revertedWithCustomError(helper, "InvalidBlock");
    const block = encodeBalanceBlock(ethers.ZeroHash, ethers.MaxUint256);
    let failure;
    try { await helper.measure.staticCall(block, 0, 0); } catch (error: any) { failure = error; }
    expect(failure?.reason).eq("hook");
  });
});
