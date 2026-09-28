import { expect } from "chai";
import { deploy } from "./helpers/setup.js";
import "./helpers/matchers.js";
import {
  concat,
  encodeAssetBlock,
  encodeCodesBlock,
  pad32,
} from "./helpers/blocks.js";

describe("AssetCodes", () => {
  it("returns empty output for empty input and rejects a truncated trailing item", async () => {
    const query = await deploy("TestAssetCodesQuery");
    expect(await query["assetCodes(bytes)"].staticCall("0x")).to.equal("0x");
    const input = concat(encodeAssetBlock(await query.allowedAssetId()), "0x01");
    await expect(query["assetCodes(bytes)"].staticCall(input))
      .to.be.revertedWithCustomError(query, "InvalidBlock");
  });

  it("returns one codes block for one asset query", async () => {
    const query = await deploy("TestAssetCodesQuery");
    const asset = await query.allowedAssetId();

    const result: string = await query["assetCodes(bytes)"].staticCall(
      encodeAssetBlock(asset),
    );

    expect(result).to.equal(encodeCodesBlock(0xa0000001n));
  });

  it("maps multiple asset blocks into matching state codes in order", async () => {
    const query = await deploy("TestAssetCodesQuery");
    const asset = await query.allowedAssetId();
    const otherAsset = pad32(0xDEADn);

    const input = concat(
      encodeAssetBlock(asset),
      encodeAssetBlock(otherAsset),
    );

    const result: string = await query["assetCodes(bytes)"].staticCall(input);

    expect(result).to.equal(concat(
      encodeCodesBlock(0xa0000001n),
      encodeCodesBlock(0xa0000000n),
    ));
  });
});
