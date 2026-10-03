import { expect } from "chai";
import { ethers } from "ethers";
import { deploy } from "./helpers/setup.js";
import { Keys, encodeBlock, concat } from "./helpers/blocks.js";
import "./helpers/matchers.js";

const layouts: [keyof typeof Keys, number][] = [
  ["Account", 1],
  ["Asset", 1],
  ["Node", 1],
  ["Status", 1],
  ["Limits", 1],
  ["AssetAmount", 2],
  ["AssetLiability", 2],
  ["AccountAsset", 2],
  ["HostAsset", 2],
  ["Bootstrap", 3],
  ["Allocation", 3],
  ["Allowance", 3],
  ["Custody", 3],
  ["AccountAmount", 3],
  ["HostAmount", 3],
  ["HostAccountAsset", 3],
  ["Quote", 4],
  ["Transaction", 4],
  ["HostAccountAmount", 4],
  ["Position", 5]
];
const fields = [ethers.MaxUint256, 1n << 255n, 0x123456789abcdefn, (1n << 128n) + 7n, 0n]
  .map(value => ethers.toBeHex(value, 32));

describe("Additional cursor codecs", () => {
  let helper: Awaited<ReturnType<typeof deploy>>;
  before(async () => { helper = await deploy("TestCodecAdditions"); });

  for (const [kind, [name, count]] of layouts.entries()) {
    it(`creates ${name} with exact field order and zero padding`, async () => {
      const expected = encodeBlock(Keys[name], concat(...fields.slice(0, count)));
      expect(await helper.fixedBlock(kind, fields)).deep.eq([expected, ethers.ZeroHash]);
    });
  }

  it("wraps memory and sliced calldata payloads, including empty and unaligned sizes", async () => {
    const keys = ["0x12345678", Keys.List, Keys.Bytes, Keys.String];
    for (const size of [0, 1, 23, 24, 31, 32, 33, 65, 257]) {
      const data = "0x" + "a5".repeat(size);
      for (const [kind, key] of keys.entries()) {
        for (const memory of [false, true]) {
          expect(await helper.payloadBlock(kind, key, data, memory))
            .deep.eq([encodeBlock(key, data), ethers.ZeroHash]);
        }
      }
    }
    for (const memory of [false, true]) {
      await expect(helper.oversized(memory)).to.be.revertedWithCustomError(helper, "ValueOverflow");
    }
  });

  const decoded: [keyof typeof Keys, number][] = [["Status", 1], ["HostAmount", 3], ["HostAccountAmount", 4]];
  for (const [kind, [name, count]] of decoded.entries()) {
    it(`unpacks ${name}, preserving metadata and bounding the entire block`, async () => {
      const block = encodeBlock(Keys[name], concat(...fields.slice(0, count)));
      const size = ethers.dataLength(block);
      const source = concat(block, "0xaabbcc");
      expect(await helper.unpack(kind, source, size + 3))
        .deep.eq([[...fields.slice(0, count), ...Array(4 - count).fill(ethers.ZeroHash)], BigInt(size), 3n, 0xabcdefn]);
      // Valid physical data beyond the logical end must not make a short cursor valid.
      for (const length of [8, size - 1]) {
        await expect(helper.unpack(kind, source, length)).to.be.revertedWithCustomError(helper, "OutOfBounds");
        await expect(helper.unpack(kind, ethers.dataSlice(block, 0, length), length))
          .to.be.revertedWithCustomError(helper, "OutOfBounds");
      }
      for (const bad of [encodeBlock("0x12345678", ethers.dataSlice(block, 8)),
        encodeBlock(Keys[name], concat(...fields.slice(0, count), ethers.ZeroHash))]) {
        await expect(helper.unpack(kind, bad, ethers.dataLength(bad)))
          .to.be.revertedWithCustomError(helper, "InvalidBlock");
      }
    });
  }

  it("passes each unpacker's returned cursor directly into the next", async () => {
    const source = concat(...decoded.map(([name, count]) => encodeBlock(Keys[name], concat(...fields.slice(0, count)))));
    expect(await helper.chain(source)).deep.eq([
      BigInt(fields[0]), BigInt(fields[0]), fields[1], fields[2], BigInt(fields[3]), 0n,
    ]);
  });

  it("raw expects compare only their width, accept unaligned abs and keep EVM zero-padding", async () => {
    const data = "0x" + "ab".repeat(65);
    for (const width of [1, 2, 4, 8, 16, 32]) {
      // Bytes after the selected width are deliberately different.
      const expected = "0x" + "ab".repeat(width) + "cd".repeat(32 - width);
      await helper.expectAt(data, 1, width, expected);
      await expect(helper.expectAt(data, 1, width, ethers.ZeroHash))
        .to.be.revertedWithCustomError(helper, "UnexpectedValue");
      for (const abs of [1n << 32n, 1n << 255n, ethers.MaxUint256]) {
        await helper.expectAbs(abs, width, ethers.ZeroHash);
        await expect(helper.expectAbs(abs, width, "0xff" + "00".repeat(31)))
          .to.be.revertedWithCustomError(helper, "UnexpectedValue");
      }
    }
  });
});
