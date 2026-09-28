import { expect } from "chai";
import { ethers } from "ethers";
import { deploy } from "./helpers/setup.js";
import { concat, encodeBlock, encodeCodesBlock, encodeStatusBlock, exactSpec, Keys } from "./helpers/blocks.js";

describe("CODES block", () => {
  it("publishes a distinct exact one-word layout", async () => {
    const helper = await deploy("TestCodesBlock");
    const key = ethers.id("#codes").slice(0, 10);
    expect(Array.from(await helper.layout())).to.deep.equal([
      key, exactSpec(key, 32), (BigInt(key) << 32n) | 32n, 40n, "uint codes",
    ]);
  });

  it("preserves every packed bit through creators, writers, and cursor consumers", async () => {
    const helper = await deploy("TestCodesBlock");
    for (const codes of [0n, 0xa0000000n, 0xa0000001n, 80n | (0xa0000001n << 32n), ethers.MaxUint256]) {
      const encoded = encodeCodesBlock(codes);
      for (const capacity of [0, 40]) {
        expect(Array.from(await helper.encode(codes, capacity))).to.deep.equal([encoded, encoded, encoded]);
      }
      const source = concat(encoded, encodeCodesBlock(0xa0000000n));
      for (const execution of [false, true]) {
        expect(Array.from(await helper.decode(source, 80, execution))).to.deep.equal([codes, 40n, 40n]);
      }
    }
  });

  it("rejects incorrect keys, widths, and truncation in both consuming APIs", async () => {
    const helper = await deploy("TestCodesBlock");
    for (const execution of [false, true]) {
      for (const malformed of [encodeStatusBlock(1n), encodeBlock(Keys.Codes, "0x" + "00".repeat(31)),
        encodeBlock(Keys.Codes, "0x" + "00".repeat(33))]) {
        await expect(helper.decode(malformed, ethers.dataLength(malformed), execution))
          .to.be.revertedWithCustomError(helper, "InvalidBlock");
      }
      const valid = encodeCodesBlock(0xa0000001n);
      await expect(helper.decode(valid, 39, execution)).to.be.revertedWithCustomError(helper, "OutOfBounds");
      await expect(helper.decode(ethers.dataSlice(valid, 0, 39), 39, execution))
        .to.be.revertedWithCustomError(helper, "OutOfBounds");
    }
  });
});
