import { expect } from "chai";
import { ethers } from "ethers";
import { deploy } from "./helpers/setup.js";
import { encodeContextBlock, encodePositionBlock, encodeBookPortBlock,
  encodeAccountAmountBlock, encodeUserAccount } from "./helpers/blocks.js";
import "./helpers/matchers.js";

describe("BookHook entrypoints", () => {
  const from = encodeUserAccount("0x11");
  const to = encodeUserAccount("0x22");
  const asset = ethers.toBeHex(1n, 32);
  const liability = ethers.toBeHex(2n, 32);
  let host: any;
  before(async () => { host = await deploy("TestBookHook"); });

  it("books both position legs to the active account through a custom book hook", async () => {
    await expect(host.book(encodeContextBlock(from, encodePositionBlock(asset, 100n, liability, 40n), "0x")))
      .to.emit(host, "Applied").withArgs(from, from, asset, 100n, liability, 40n);
  });

  it("books transfers and single-sided entries with explicit zero quantities", async () => {
    for (const source of [from, ethers.ZeroHash]) {
      for (const destination of [to, ethers.ZeroHash]) {
        await expect(host.portBook(encodeBookPortBlock(
          encodeAccountAmountBlock(source, asset, source === ethers.ZeroHash ? 0n : 7n),
          encodeAccountAmountBlock(destination, asset, destination === ethers.ZeroHash ? 0n : 7n),
        )))
          .to.emit(host, "Applied").withArgs(source, destination, asset,
            destination === ethers.ZeroHash ? 0n : 7n, asset, source === ethers.ZeroHash ? 0n : 7n);
      }
    }
  });

  it("maps port booking debit and credit blocks to liability and asset legs", async () => {
    await expect(host.portBook(encodeBookPortBlock(
      encodeAccountAmountBlock(from, liability, 40n), encodeAccountAmountBlock(to, asset, 100n),
    ))).to.emit(host, "Applied").withArgs(from, to, asset, 100n, liability, 40n);
  });

  it("keeps booking counterparty validation before the custom hook", async () => {
    await expect(host.book(encodeContextBlock(from, encodePositionBlock(asset, 100n, liability, 40n, to), "0x")))
      .to.be.revertedWithCustomError(host, "UnexpectedValue");
  });
});
