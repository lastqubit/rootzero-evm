import { expect } from "chai";
import { ethers } from "ethers";
import { deploy } from "./helpers/setup.js";
import { concat, encodeBlock, encodeRootedBlock, encodeCodesBlock, exactSpec, Keys } from "./helpers/blocks.js";
import "./helpers/matchers.js";

describe("Rooted schema", () => {
  it("publishes the canonical key and fixed three-word layout", async () => {
    const helper = await deploy("TestRooted");
    expect(Array.from(await helper.layoutRooted())).deep.eq([
      ethers.id("#rooted").slice(0, 10), exactSpec(Keys.Rooted, 96),
      (BigInt(Keys.Rooted) << 32n) | 96n, 104n, "bytes32 account, uint deadline, uint value",
    ]);
  });
  it("round-trips full-width fields through creators, growing writers, execution and bounded decoders", async () => {
    const helper = await deploy("TestRooted");
    for (const account of [ethers.ZeroHash, ethers.id("account")])
      for (const [deadline, value] of [[0n, 0n], [123n, 456n], [ethers.MaxUint256, ethers.MaxUint256]]) {
        const block = encodeRootedBlock(account, deadline, value);
        for (const capacity of [0, 40, 104, 512])
          expect(Array.from(await helper.encode(account, deadline, value, capacity))).deep.eq([block, block, block]);
        for (const execution of [false, true])
          expect(Array.from(await helper.decode(concat(block, encodeCodesBlock(1n)), 144, execution)))
            .deep.eq([account, deadline, value, 104n, 40n]);
      }
  });
  it("rejects wrong keys, wrong widths and bounded truncation", async () => {
    const helper = await deploy("TestRooted");
    const block = encodeRootedBlock(ethers.ZeroHash, 1n, 2n);
    for (const execution of [false, true]) {
      for (const bad of [encodeBlock(Keys.Bootstrap, ethers.dataSlice(block, 8)),
        ...[0, 95, 97].map(size => encodeBlock(Keys.Rooted, "0x" + "00".repeat(size)))])
        await expect(helper.decode(bad, ethers.dataLength(bad), execution)).revertedWithCustomError(helper, "InvalidBlock");
      await expect(helper.decode(block, 103, execution)).revertedWithCustomError(helper, "OutOfBounds");
    }
  });
  it("Logs.rooted emits full-width codes and a single Rooted block", async () => {
    const helper = await deploy("TestRooted");
    const account = ethers.id("root-account");
    for (const [deadline, value] of [[0n, 0n], [123n, 456n], [ethers.MaxUint256, ethers.MaxUint256]])
      for (const codes of [0n, 80n, ethers.MaxUint256]) {
        const receipt = await (await helper.emitRooted(codes, account, deadline, value)).wait();
        expect(receipt.logs).to.have.length(1);
        expect(receipt.logs[0].topics).deep.eq([]);
        expect(receipt.logs[0].data).eq(concat(ethers.toBeHex(codes, 32), encodeRootedBlock(account, deadline, value)));
        expect(ethers.dataLength(receipt.logs[0].data)).eq(136);
      }
  });
});
