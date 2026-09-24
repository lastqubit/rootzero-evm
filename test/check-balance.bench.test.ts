import { expect } from "chai";
import { ethers } from "ethers";
import { deploy } from "./helpers/setup.js";
import { concat, encodeBalanceBlock, encodeAssetLimitsBlock, encodeContextBlock } from "./helpers/blocks.js";

describe("CheckBalance execution benchmark", function () {
  this.timeout(120_000);
  it("compares normal and memory execution over increasing batches", async () => {
    const host = await deploy("TestCheckBalance");
    const asset = ethers.toBeHex(1n, 32);
    const rows: { count: number; normal: string; memory: string }[] = [];
    for (const count of [1, 8, 32]) {
      const state = concat(...Array(count).fill(encodeBalanceBlock(asset, 100n)));
      const input = concat(...Array(count).fill(encodeAssetLimitsBlock(asset, 90n, 110n)));
      const context = encodeContextBlock(ethers.ZeroHash, state, input);
      expect((await host.checkBalance.staticCall(context))[0]).to.equal(state);
      expect((await host.checkMemory(state, input, 0n))[1]).to.equal(state);
      rows.push({ count, normal: (await host.checkBalance.estimateGas(context)).toString(),
        memory: (await host.checkMemory.estimateGas(state, input, 0n)).toString() });
    }
    // End-to-end estimates include different wrapper calldata/return encodings.
    console.table(rows);
  });
});
