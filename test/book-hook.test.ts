import { expect } from "chai";
import { ethers } from "ethers";
import { deploy } from "./helpers/setup.js";
import { encodeLimitsBlock, encodeContextBlock, encodePositionBlock, encodeBookPortPair,
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
    await expect(host.settle(encodeContextBlock(from, encodePositionBlock(asset, 100n, liability, 40n), "0x")))
      .to.emit(host, "Applied").withArgs(from, from, asset, 100n, liability, 40n);
  });

  it("books transfers and single-sided entries with explicit zero quantities", async () => {
    for (const source of [from, ethers.ZeroHash]) {
      for (const destination of [to, ethers.ZeroHash]) {
        await expect(host.portBook(encodeBookPortPair(
          encodeAccountAmountBlock(source, asset, source === ethers.ZeroHash ? 0n : 7n),
          encodeAccountAmountBlock(destination, asset, destination === ethers.ZeroHash ? 0n : 7n),
        )))
          .to.emit(host, "Applied").withArgs(source, destination, asset,
            destination === ethers.ZeroHash ? 0n : 7n, asset, source === ethers.ZeroHash ? 0n : 7n);
      }
    }
  });

  it("maps port booking debit and credit blocks to liability and asset legs", async () => {
    await expect(host.portBook(encodeBookPortPair(
      encodeAccountAmountBlock(from, liability, 40n), encodeAccountAmountBlock(to, asset, 100n),
    ))).to.emit(host, "Applied").withArgs(from, to, asset, 100n, liability, 40n);
  });

  it("passes opaque account identifiers to the custom book hook", async () => {
    const tx = host.settle(encodeContextBlock(from, encodePositionBlock(asset, 100n, liability, 40n, asset), "0x"));
    await expect(tx).to.emit(host, "Applied").withArgs(from, asset, liability, 40n, liability, 40n);
    await expect(tx).to.emit(host, "Applied").withArgs(asset, from, asset, 100n, asset, 100n);
  });

  it("rejects settlement input and reverts custom book hook effects", async () => {
    await expect(host.settle(encodeContextBlock(from,
      encodePositionBlock(asset, 100n, liability, 40n), encodeLimitsBlock(101n, 40n))))
      .to.be.revertedWithCustomError(host, "OutOfBounds");
  });
});
