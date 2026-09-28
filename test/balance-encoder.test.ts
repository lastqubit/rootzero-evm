import { expect } from "chai";
import { ethers } from "ethers";
import { deploy } from "./helpers/setup.js";
import { concat, encodeBalanceBlock, encodeBytesBlock } from "./helpers/blocks.js";

describe("BALANCE encoder migration", () => {
  it("mixes cursor BALANCE writes with existing writers while preserving growth and metadata", async () => {
    const helper = await deploy("TestBalanceEncoder");
    const a = encodeBalanceBlock(ethers.toBeHex(1, 32), 123n);
    const b = encodeBalanceBlock(ethers.toBeHex(2, 32), 456n);
    for (const execution of [false, true]) for (const first of [false, true]) for (const capacity of [0, 1, 72, 1024]) for (const size of [0, 65]) {
      const payload = "0x" + "ab".repeat(size), bytes = encodeBytesBlock(payload);
      const [output, metadata] = await helper.mixed(execution, first, capacity, payload);
      expect(output).eq(concat(first ? "0x" : bytes, a, bytes, b));
      expect(metadata).eq(0xabcdefn);
    }
  });
  it("matches the old encoding at unaligned offsets without trailing scratch", async () => {
    const old = await deploy("TestBalanceEncoderPrevious"), current = await deploy("TestBalanceEncoder");
    for (const asset of [ethers.ZeroHash, ethers.toBeHex(17, 32), ethers.toBeHex(ethers.MaxUint256, 32)]) {
      for (const amount of [0n, 1n, 1n << 255n, ethers.MaxUint256]) for (const offset of [0, 1, 31, 32]) {
        const expected = encodeBalanceBlock(asset, amount);
        for (const helper of [old, current]) {
          const [created, written] = await helper.inspect(asset, amount, offset);
          expect(created).eq(expected);
          expect(written).eq(concat("0x" + "ef".repeat(offset), expected, "0x" + "ef".repeat(32)));
        }
      }
    }
  });

  it("preserves Encoder growth, reservation, and final output lengths", async () => {
    const helper = await deploy("TestBalanceEncoder");
    const asset = ethers.toBeHex(3, 32);
    for (const count of [0, 1, 4, 16]) for (const capacity of [0, 1, 71, 72, 1152]) {
      expect(await helper.append(asset, ethers.MaxUint256, count, capacity))
        .eq(concat(...Array(count).fill(encodeBalanceBlock(asset, ethers.MaxUint256))));
    }
  });
});
