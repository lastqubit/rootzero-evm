import { expect } from "chai";
import { ethers } from "ethers";
import { deploy, queryId } from "./helpers/setup.js";
import "./helpers/matchers.js";
import {
  concat, encodeAssetBlock, encodeBlock, encodeCodesBlock, encodeEntityBlock,
  encodeLabelBlock, encodeNodeBlock, endpointSpecs, exactSpec, Keys,
} from "./helpers/blocks.js";

describe("GetEntityCodes", () => {
  let query: Awaited<ReturnType<typeof deploy>>;

  before(async () => { query = await deploy("TestEntityCodesQuery"); });

  it("publishes its entity input, codes output, and default label", async () => {
    const id = await queryId("entityCodes(bytes)", query);
    await expect(query.deploymentTransaction()).to.emit(query, "Endpoint").withArgs(
      await query.host(), id,
      ...endpointSpecs({ input: Keys.Entity, inputHint: 32, output: exactSpec(Keys.Codes, 32) }),
    );
    await expect(query.deploymentTransaction()).to.emit(query, "Annotation")
      .withArgs(id, encodeLabelBlock(ethers.ZeroHash, "entityCodes"));
  });

  it("returns empty output for empty input", async () => {
    expect(await query["entityCodes(bytes)"]("0x")).to.equal("0x");
  });

  it("distinguishes unknown conditions from explicitly inactive", async () => {
    expect(await query["entityCodes(bytes)"](encodeEntityBlock(0n)))
      .to.equal(encodeCodesBlock(0n));
    expect(await query["entityCodes(bytes)"](encodeEntityBlock(2n)))
      .to.equal(encodeCodesBlock(0xa0000000n));
  });

  it("preserves order, duplicates, unknown entries, and full-width entity IDs", async () => {
    const input = concat(...[1n, 99n, 2n, ethers.MaxUint256, 1n].map(encodeEntityBlock));
    expect(await query["entityCodes(bytes)"](input)).to.equal(concat(
      ...[0xa0000001n, 0n, 0xa0000000n, 0xa0000010n, 0xa0000001n].map(encodeCodesBlock),
    ));
  });

  it("coexists with the stricter assetCodes query", async () => {
    expect(await query["assetCodes(bytes)"](encodeAssetBlock(ethers.ZeroHash)))
      .to.equal(encodeCodesBlock(0xa0000000n));
  });

  it("rejects other block kinds, incorrect widths, and partial trailing entries", async () => {
    const valid = encodeEntityBlock(1n);
    for (const [malformed, error] of [
      [encodeNodeBlock(1n), "InvalidBlock"],
      [encodeAssetBlock(ethers.ZeroHash), "InvalidBlock"],
      [encodeBlock(Keys.Entity, "0x"), "InvalidBlock"],
      [encodeBlock(Keys.Entity, "0x" + "00".repeat(31)), "InvalidBlock"],
      [encodeBlock(Keys.Entity, "0x" + "00".repeat(33)), "InvalidBlock"],
      ["0x01", "InvalidBlock"],
      [ethers.dataSlice(valid, 0, 39), "OutOfBounds"],
    ]) {
      await expect(query["entityCodes(bytes)"](malformed)).to.be.revertedWithCustomError(query, error);
      await expect(query["entityCodes(bytes)"](concat(valid, malformed)))
        .to.be.revertedWithCustomError(query, error);
    }
  });
});
