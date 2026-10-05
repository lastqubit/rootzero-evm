import { expect } from "chai";
import { ethers } from "ethers";
import { deploy } from "./helpers/setup.js";
import { concat, encodeBlock, encodePipelineBlock, encodeCodesBlock, exactSpec, Keys } from "./helpers/blocks.js";
import "./helpers/matchers.js";

describe("Pipeline schema", () => {
  it("publishes the canonical key and fixed two-word layout", async () => {
    const helper = await deploy("TestPipelineBlock");
    expect(Array.from(await helper.layoutPipeline())).deep.eq([
      ethers.id("#pipeline").slice(0, 10), exactSpec(Keys.Pipeline, 64),
      (BigInt(Keys.Pipeline) << 32n) | 64n, 72n, "bytes32 account, uint budget",
    ]);
  });
  it("round-trips full-width fields through creators, growing writers, execution and bounded decoders", async () => {
    const helper = await deploy("TestPipelineBlock");
    for (const account of [ethers.ZeroHash, ethers.id("account")])
      for (const value of [0n, 456n, ethers.MaxUint256]) {
        const block = encodePipelineBlock(account, value);
        for (const capacity of [0, 40, 72, 512])
          expect(Array.from(await helper.encode(account, value, capacity))).deep.eq([block, block, block]);
        for (const execution of [false, true])
          expect(Array.from(await helper.decode(concat(block, encodeCodesBlock(1n)), 112, execution)))
            .deep.eq([account, value, 72n, 40n]);
      }
  });
  it("rejects wrong keys, wrong widths and bounded truncation", async () => {
    const helper = await deploy("TestPipelineBlock");
    const block = encodePipelineBlock(ethers.ZeroHash, 2n);
    for (const execution of [false, true]) {
      for (const bad of [encodeBlock(Keys.Bootstrap, ethers.dataSlice(block, 8)),
        encodeBlock(ethers.id("#rooted").slice(0, 10), "0x" + "00".repeat(96)),
        encodeBlock(ethers.id("#rooted").slice(0, 10), ethers.dataSlice(block, 8)),
        ...[0, 63, 65].map(size => encodeBlock(Keys.Pipeline, "0x" + "00".repeat(size)))])
        await expect(helper.decode(bad, ethers.dataLength(bad), execution)).revertedWithCustomError(helper, "InvalidBlock");
      await expect(helper.decode(block, 71, execution)).revertedWithCustomError(helper, "OutOfBounds");
    }
  });
  it("Logs.pipeline emits full-width codes and a single Pipeline block", async () => {
    const helper = await deploy("TestPipelineBlock");
    const account = ethers.id("root-account");
    for (const value of [0n, 456n, ethers.MaxUint256])
      for (const codes of [0n, 80n, ethers.MaxUint256]) {
        const receipt = await (await helper.emitPipeline(codes, account, value)).wait();
        expect(receipt.logs).to.have.length(1);
        expect(receipt.logs[0].topics).deep.eq([]);
        expect(receipt.logs[0].data).eq(concat(ethers.toBeHex(codes, 32), encodePipelineBlock(account, value)));
        expect(ethers.dataLength(receipt.logs[0].data)).eq(104);
      }
  });
});
