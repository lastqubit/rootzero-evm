import { expect } from "chai";
import { ethers } from "ethers";
import { deploy } from "./helpers/setup.js";
import { concat, encodeBlock, encodeEntityBlock, encodeNodeBlock, exactSpec, Keys } from "./helpers/blocks.js";

describe("ENTITY block", () => {
  it("publishes a distinct exact one-word layout", async () => {
    const helper = await deploy("TestEntityBlock");
    const key = ethers.id("#entity").slice(0, 10);
    expect(Array.from(await helper.describeBlock())).to.deep.equal([
      key, exactSpec(key, 32), (BigInt(key) << 32n) | 32n, 40n, "uint entity",
    ]);
  });

  it("preserves full-width identifiers through creators, writers, and cursor consumers", async () => {
    const helper = await deploy("TestEntityBlock");
    for (const entity of [0n, 1n, 1n << 128n, (1n << 255n) | 80n, ethers.MaxUint256]) {
      const encoded = encodeEntityBlock(entity);
      for (const capacity of [0, 40]) {
        expect(Array.from(await helper.encode(entity, capacity))).to.deep.equal([encoded, encoded, encoded]);
      }
      const source = concat(encoded, encodeEntityBlock(0xa0000000n));
      for (const execution of [false, true]) {
        expect(Array.from(await helper.decode(source, 80, execution))).to.deep.equal([entity, 40n, 40n]);
      }
    }
  });

  it("rejects incorrect keys, widths, and truncation in both consuming APIs", async () => {
    const helper = await deploy("TestEntityBlock");
    for (const execution of [false, true]) {
      for (const malformed of [encodeNodeBlock(1n), encodeBlock(Keys.Entity, "0x" + "00".repeat(31)),
        encodeBlock(Keys.Entity, "0x" + "00".repeat(33))]) {
        await expect(helper.decode(malformed, ethers.dataLength(malformed), execution))
          .to.be.revertedWithCustomError(helper, "InvalidBlock");
      }
      const valid = encodeEntityBlock(0xa0000001n);
      await expect(helper.decode(valid, 39, execution)).to.be.revertedWithCustomError(helper, "OutOfBounds");
      await expect(helper.decode(ethers.dataSlice(valid, 0, 39), 39, execution))
        .to.be.revertedWithCustomError(helper, "OutOfBounds");
    }
  });
});
