import { expect } from "chai";
import { ethers } from "ethers";
import { deploy } from "./helpers/setup.js";
import { concat, encodeBlock, encodeEntityBlock, encodeTrustBlock, exactSpec, Keys } from "./helpers/blocks.js";
import "./helpers/matchers.js";

describe("TRUST block", () => {
  it("publishes an exact one-word state layout", async () => {
    const helper = await deploy("TestTrustBlock");
    const key = ethers.id("#trust").slice(0, 10);
    expect(Array.from(await helper.describeBlock())).to.deep.equal([
      key, exactSpec(key, 32), (BigInt(key) << 32n) | 32n, 40n, "uint id",
    ]);
  });

  it("preserves full-width IDs through creators, writers, state and calldata consumers", async () => {
    const helper = await deploy("TestTrustBlock");
    for (const id of [0n, 1n, 1n << 128n, (0x0203n << 240n) | 0x1001n, ethers.MaxUint256]) {
      const encoded = encodeTrustBlock(id);
      for (const capacity of [0, 40]) {
        expect(Array.from(await helper.encode(id, capacity))).to.deep.equal([encoded, encoded, encoded]);
      }
      const source = concat(encoded, encodeTrustBlock(0xa0000000n));
      for (const mode of [0, 1, 2]) {
        expect(Array.from(await helper.decode(source, 80, mode))).to.deep.equal([id, 40n, 40n]);
      }
    }
  });

  it("is distinct from ENTITY and rejects wrong keys, widths and truncation", async () => {
    const helper = await deploy("TestTrustBlock");
    for (const mode of [0, 1]) {
      for (const malformed of [encodeEntityBlock(1n), encodeBlock(Keys.Trust, "0x" + "00".repeat(31)),
        encodeBlock(Keys.Trust, "0x" + "00".repeat(33))]) {
        await expect(helper.decode(malformed, ethers.dataLength(malformed), mode))
          .to.be.revertedWithCustomError(helper, "InvalidBlock");
      }
      const valid = encodeTrustBlock(0xa0000001n);
      await expect(helper.decode(valid, 39, mode)).to.be.revertedWithCustomError(helper, "OutOfBounds");
    }
    await expect(helper.decode(encodeEntityBlock(1n), 40, 2)).to.be.revertedWithCustomError(helper, "InvalidBlock");
  });

  it("is read from the state lane only, never from input", async () => {
    const helper = await deploy("TestTrustBlock");
    // The empty state lane has no TRUST header, so decoding fails instead of reading the input block.
    await expect(helper.stateOnly(encodeTrustBlock(7n))).to.be.revertedWithCustomError(helper, "InvalidBlock");
  });

  it("expects a vouched ID without returning it, from cursors and the state lane", async () => {
    const helper = await deploy("TestTrustBlock");
    const asset = (0x0203n << 240n) | 0x1001n;
    const source = concat(encodeTrustBlock(asset), encodeTrustBlock(7n));
    for (const mode of [0, 1]) {
      expect(Array.from(await helper.expectId(source, asset, mode))).deep.eq([40n, 40n]);
      await expect(helper.expectId(source, asset + 1n, mode)).to.be.revertedWithCustomError(helper, "UnexpectedValue");
      await expect(helper.expectId(encodeEntityBlock(asset), asset, mode)).to.be.revertedWithCustomError(helper, "InvalidBlock");
    }
  });

  it("expects a vouched bytes32 ID, such as an asset, through the word overloads", async () => {
    const helper = await deploy("TestTrustBlock");
    for (const id of [0n, 7n, (0x0203n << 240n) | 0x1001n, ethers.MaxUint256]) {
      const word = ethers.toBeHex(id, 32);
      const source = concat(encodeTrustBlock(id), encodeTrustBlock(7n));
      for (const mode of [0, 1]) {
        // Same consumption and result as the uint overload for the same word.
        expect(Array.from(await helper.expectWord(source, word, mode))).deep.eq([40n, 40n]);
        expect(Array.from(await helper.expectWord(source, word, mode)))
          .deep.eq(Array.from(await helper.expectId(source, id, mode)));
        const other = ethers.toBeHex(id ^ 1n, 32);
        await expect(helper.expectWord(source, other, mode)).to.be.revertedWithCustomError(helper, "UnexpectedValue");
        await expect(helper.expectWord(encodeEntityBlock(id), word, mode)).to.be.revertedWithCustomError(helper, "InvalidBlock");
      }
    }
  });
});
