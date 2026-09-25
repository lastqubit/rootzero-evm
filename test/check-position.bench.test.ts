import { expect } from "chai";
import { ethers } from "ethers";
import { deploy } from "./helpers/setup.js";
import { concat, encodePositionBlock, encodePositionLimitsBlock, encodeContextBlock } from "./helpers/blocks.js";

describe("CheckPosition execution benchmark", function () {
  this.timeout(120_000);
  it("compares normal and memory execution over increasing batches", async () => {
    const host = await deploy("TestCheckPosition");
    const asset = ethers.toBeHex(1n, 32);
    const liability = ethers.toBeHex(2n, 32);
    const rows: { count: number; normal: string; memory: string; execution: string }[] = [];
    for (const count of [0, 1, 2, 4, 8, 15, 32]) {
      const state = concat(...Array(count).fill(encodePositionBlock(asset, 100n, liability, 40n)));
      const input = concat(...Array(count).fill(encodePositionLimitsBlock(asset, 100n, liability, 40n)));
      const context = encodeContextBlock(ethers.ZeroHash, state, input);
      expect((await host.checkPosition.staticCall(context))[0]).to.equal(state);
      expect((await host.checkMemory(state, input, 0n))[1]).to.equal(state);
      const measured = await host.measureMemory(state, input, 123n);
      expect(Array.from(measured).slice(1)).to.deep.equal([true, state, 123n]);
      rows.push({ count, normal: (await host.checkPosition.estimateGas(context)).toString(),
        memory: (await host.checkMemory.estimateGas(state, input, 0n)).toString(),
        execution: measured[0].toString() });
    }
    // End-to-end estimates include different wrapper calldata/return encodings.
    // execution measures the internal call with gasleft, excluding those costs.
    console.table(rows);
  });
});
