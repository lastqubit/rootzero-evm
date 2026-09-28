import { expect } from "chai";
import "./helpers/matchers.js";
import { ethers } from "ethers";
import { deploy } from "./helpers/setup.js";
import { Keys } from "./helpers/blocks.js";

const word = (value: number | bigint) => ethers.toBeHex(value, 32);
const block = (key: string, fields: (number | bigint)[]) =>
  ethers.concat([key, ethers.toBeHex(fields.length * 32, 4), ...fields.map(word)]);

describe("MemoryBlocks", () => {
  it("reads empty and sequential balance streams with packed cursors", async () => {
    const helper = await deploy("TestMemoryBlocks");
    expect(Array.from(await helper.balances("0x"))).deep.eq([word(0), 0n, 0n]);
    const source = ethers.concat([block(Keys.Balance, [3, 7]), block(Keys.Balance, [5, 11])]);
    expect(Array.from(await helper.balances(source))).deep.eq([word(6), 18n, 144n]);
  });

  it("matches legacy position fields and returns an independent struct", async () => {
    const helper = await deploy("TestMemoryBlocks");
    const source = block(Keys.Position, [1, ethers.MaxUint256, 3, 4, 5]);
    const result = await helper.position(ethers.concat([source, block(Keys.Balance, [6, 7])]));
    expect(Array.from(result[0])).deep.eq([word(1), ethers.MaxUint256, word(3), 4n, word(5)]);
    expect(result[1]).eq(168n);
    expect(result[2]).eq(true);
    expect(Array.from(await helper.comparePosition(source))).deep.eq([true, true]);
  });

  it("preserves end and metadata and rejects logical truncation or reversed ranges", async () => {
    const helper = await deploy("TestMemoryBlocks");
    for (const [key, fields, size, position] of [
      [Keys.Balance, [1, 2], 72, false],
      [Keys.Position, [1, 2, 3, 4, 5], 168, true],
    ] as const) {
      const source = block(key, [...fields]);
      expect(Array.from(await helper.bounded(source, 0, size, 0x1234n << 64n, position)))
        .deep.eq([BigInt(size), BigInt(size), 0x1234n]);
      for (const length of [0, 1, 7, 8, size - 1]) {
        await expect(helper.bounded(source, 0, length, 0, position)).revertedWithCustomError(helper, "OutOfBounds");
      }
      await expect(helper.bounded(source, size, 0, 0, position)).revertedWithCustomError(helper, "OutOfBounds");
    }
  });

  it("rejects wrong headers, short allocations, and a partial trailing block", async () => {
    const helper = await deploy("TestMemoryBlocks");
    const balance = block(Keys.Balance, [1, 2]);
    await expect(helper.balances(block(Keys.Position, [1, 2]))).revertedWithCustomError(helper, "InvalidBlock");
    await expect(helper.balances(ethers.concat([Keys.Balance, "0x0000003f", word(1), word(2)])))
      .revertedWithCustomError(helper, "InvalidBlock");
    await expect(helper.position(block(Keys.Balance, [1, 2, 3, 4, 5])))
      .revertedWithCustomError(helper, "InvalidBlock");
    await expect(helper.position("0x")).revertedWithCustomError(helper, "OutOfBounds");
    await expect(helper.balances(ethers.dataSlice(balance, 0, 71))).revertedWithCustomError(helper, "OutOfBounds");
    await expect(helper.balances(ethers.concat([balance, "0xff"]))).revertedWithCustomError(helper, "OutOfBounds");
  });
});
