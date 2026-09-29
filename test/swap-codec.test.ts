import { expect } from "chai";
import { ethers } from "ethers";
import { deploy } from "./helpers/setup.js";
import { concat, encodeAssetBlock, encodeBlock, encodeBytesBlock, encodeListBlock, encodeSwapBlock, Keys, pad32, rangedSpec } from "./helpers/blocks.js";
import "./helpers/matchers.js";

describe("SWAP codec", () => {
  const asset = ethers.toBeHex(1, 32), output = ethers.toBeHex(2, 32);
  it("defines the shared schema and minimum structural size", async () => {
    const codec = await deploy("TestSwapCodec");
    expect(Array.from(await codec.describeBlock())).deep.eq([
      ethers.id("#swap").slice(0, 10), rangedSpec(Keys.Swap, 72, 0, 256), 80n,
      "bytes32 asset, uint amount, many #asset as hops",
    ]);
  });

  it("round-trips all writer and execution paths with clean child ranges and preserved parent metadata", async () => {
    const codec = await deploy("TestSwapCodec");
    for (const hops of [[], [output], [asset, output, asset]]) {
      const stream = concat(...hops.map(encodeAssetBlock));
      const list = encodeListBlock(...hops.map(encodeAssetBlock));
      const swap = encodeSwapBlock(asset, ethers.MaxUint256, ...hops);
      for (const capacity of [0, ethers.dataLength(swap)]) for (let mode = 0; mode < 6; mode++) {
        expect(await codec.encode(asset, ethers.MaxUint256, stream, list, capacity, mode)).eq(swap);
      }
      const source = concat("0xff", swap, swap);
      for (const execution of [false, true]) {
        expect(Array.from(await codec.decode(source, ethers.dataLength(source), 1, execution))).deep.eq([
          asset, ethers.MaxUint256, stream, BigInt(1 + ethers.dataLength(swap)), 0xa5n,
        ]);
      }
    }
  });

  it("rejects malformed parents, missing or incorrect final children, and logical truncation", async () => {
    const codec = await deploy("TestSwapCodec");
    const valid = encodeSwapBlock(asset, 1n, output);
    const list = encodeListBlock(encodeAssetBlock(output));
    for (const execution of [false, true]) {
      for (const bad of [
        encodeBlock(Keys.Call, concat(asset, pad32(1n), list)),
        encodeBlock(Keys.Swap, asset),
        encodeBlock(Keys.Swap, concat(asset, pad32(1n))),
        encodeBlock(Keys.Swap, concat(asset, pad32(1n), encodeBytesBlock(encodeAssetBlock(output)))),
        encodeBlock(Keys.Swap, concat(asset, pad32(1n), list, "0xff")),
      ]) {
        await expect(codec.decode(bad, ethers.dataLength(bad), 0, execution)).revertedWithCustomError(codec, "InvalidBlock");
      }
      await expect(codec.decode(valid, ethers.dataLength(valid) - 1, 0, execution)).revertedWithCustomError(codec, "OutOfBounds");
    }
  });
});
