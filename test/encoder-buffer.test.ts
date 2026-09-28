import { expect } from "chai";
import { ethers } from "ethers";
import { deploy } from "./helpers/setup.js";
import { concat, encodeBalanceBlock, encodeBytesBlock, encodeContextBlock } from "./helpers/blocks.js";

describe("Encoder growable buffers", function () {
  this.timeout(120_000);
  it("chains every cursor writer through lazy allocation, exact capacity, and growth", async () => {
    const helper = await deploy("TestEncoderBuffer");
    const account = ethers.toBeHex(7, 32);
    for (const mode of [0, 1, 2, 3, 4]) for (const size of [0, 1, 31, 32, 65]) {
      const state = "0x" + "ab".repeat(size), input = "0x" + "cd".repeat(size + 1);
      const block = mode === 0 ? encodeBalanceBlock(account, 123n) : encodeContextBlock(account, state, input);
      const blockSize = ethers.dataLength(block);
      for (const count of [0, 1, 4]) for (const capacity of [0, 1, blockSize - 1, blockSize, blockSize * count]) {
        const [, , cur, output] = await helper.measure(account, mode === 1 || mode === 2 ? encodeBytesBlock(state) : state,
          mode === 1 || mode === 2 ? encodeBytesBlock(input) : input, count, capacity, mode, false);
        expect(output).eq(concat(...Array(count).fill(block)));
        expect(cur & 0xffffffffn).eq(BigInt(count * blockSize));
        expect((cur >> 32n) & 0xffffffffn).gte(BigInt(count * blockSize));
        expect(cur >> 128n).eq(0xabcdefn);
      }
    }
  });

  it("keeps scratch inside retained allocations and clears dirty final padding", async () => {
    const helper = await deploy("TestEncoderBuffer");
    for (const capacity of [0, 1, 17, 31, 32, 68, 256]) for (const count of [1, 4, 16]) {
      const [output, padding, guard] = await helper.dirty(capacity, count);
      expect(output).eq(concat(...Array.from({ length: count }, (_, j) => "0x0102030400000001" + ethers.toBeHex(j, 1).slice(2) + "0506070800000000")));
      expect(padding).eq(ethers.ZeroHash);
      expect(guard).eq(ethers.toBeHex(0xfeed, 32));
    }
  });

  it("rejects capacity overflow before allocating", async () => {
    const helper = await deploy("TestEncoderBuffer");
    for (const [capacity, size] of [[1n << 32n, 0n], [0n, 1n << 32n], [0n, ethers.MaxUint256], [1n << 31n, (1n << 31n) + 1n]]) {
      let failed = false;
      try { await helper.overflow(capacity, size); } catch { failed = true; }
      expect(failed).eq(true);
    }
  });
});
