import { expect } from "chai";
import { ethers } from "ethers";
import { deploy } from "./helpers/setup.js";
import { concat, encodeBalanceBlock, encodeAmountBlock, encodeOutputBlock } from "./helpers/blocks.js";
import "./helpers/matchers.js";

describe("Execution finalization", () => {
  it("returns finalized output with optional logging and preserves finish/close budget behavior", async () => {
    const helper = await deploy("TestExecutionFinalization");
    for (const logging of [false, true])
    for (const close of [false, true])
      for (const budget of [0n, ethers.MaxUint256])
        for (const [initialized, capacity, count] of [
          [false, 0, 0], [true, 0, 0], [true, 512, 0], [true, 0, 3], [true, 512, 3],
        ] as const) {
          const flags = Number(close) | (Number(logging) << 1) | (Number(initialized) << 2);
          const expected = concat(...Array.from({ length: count }, (_, i) =>
            encodeBalanceBlock(ethers.toBeHex(i + 1, 32), ethers.MaxUint256 - BigInt(i))));
          const args = [flags, budget, capacity, count, "0x", "0x"] as const;
          const result = await helper.finalize.staticCall(...args);
          expect(result.output).eq(expected);
          expect(result.credit).eq(close ? budget : 0n);
          expect(result.remaining).eq(close ? 0n : budget);
          const receipt = await (await helper.finalize(...args)).wait();
          expect(receipt.logs.map((l: any) => l.data)).deep.eq(logging ? [concat("0x04", ethers.toBeHex(123, 32), ethers.ZeroHash, encodeOutputBlock(expected))] : []);
        }
  });

  it("checks consumption on close while finish permits pending sources", async () => {
    const helper = await deploy("TestExecutionFinalization");
    const pending = encodeAmountBlock(1n);
    for (const flags of [5, 7]) for (const [input, state] of [[pending, "0x"], ["0x", pending], [pending, pending]]) {
      expect((await helper.finalize.staticCall(flags & ~1, 123n, 0, 1, input, state)).remaining).eq(123n);
      await expect(helper.finalize(flags, 123n, 0, 1, input, state))
        .revertedWithCustomError(helper, "UnconsumedData");
    }
  });
  it("requires exact cursor equality, including overshot cursors", async () => {
    const helper = await deploy("TestExecutionFinalization");
    for (const position of [0n, 16n, 32n]) {
      const cursor = position | (16n << 32n);
      for (const args of [[cursor, 0n], [0n, cursor]]) {
        if (position === 16n) await helper.checkEnd(...args);
        else await expect(helper.checkEnd(...args)).revertedWithCustomError(helper, "UnconsumedData");
      }
    }
  });
});
