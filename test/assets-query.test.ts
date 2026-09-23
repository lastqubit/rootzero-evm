import { expect } from "chai";
import { deploy } from "./helpers/setup.js";
import "./helpers/matchers.js";
import {
  concat,
  encodeAssetBlock,
  encodeStatusBlock,
  pad32,
} from "./helpers/blocks.js";

describe("AssetStatus", () => {
  it("returns empty output for empty input and rejects a truncated trailing item", async () => {
    const query = await deploy("TestAssetStatusQuery");
    expect(await query["assetStatus(bytes)"].staticCall("0x")).to.equal("0x");
    const input = concat(encodeAssetBlock(await query.allowedAssetId()), "0x01");
    await expect(query["assetStatus(bytes)"].staticCall(input))
      .to.be.revertedWithCustomError(query, "OutOfBounds");
  });

  it("returns one status block for one asset query", async () => {
    const query = await deploy("TestAssetStatusQuery");
    const asset = await query.allowedAssetId();

    const result: string = await query["assetStatus(bytes)"].staticCall(
      encodeAssetBlock(asset),
    );

    expect(result).to.equal(encodeStatusBlock(1n));
  });

  it("maps multiple asset blocks into matching status codes in order", async () => {
    const query = await deploy("TestAssetStatusQuery");
    const asset = await query.allowedAssetId();
    const otherAsset = pad32(0xDEADn);

    const input = concat(
      encodeAssetBlock(asset),
      encodeAssetBlock(otherAsset),
    );

    const result: string = await query["assetStatus(bytes)"].staticCall(input);

    expect(result).to.equal(concat(
      encodeStatusBlock(1n),
      encodeStatusBlock(0n),
    ));
  });
});
