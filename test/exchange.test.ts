import { expect } from "chai";
import { ethers } from "ethers";
import { deploy, getSigner, portId } from "./helpers/setup.js";
import { concat, encodeBlock, encodeExchangeBlock, ExchangeKey, encodeSchemaBlock, exactSpec, encodeAccountAmountBlock, encodeLabelBlock, encodeUserAccount, endpointDescriptor, Keys } from "./helpers/blocks.js";
import "./helpers/matchers.js";

describe("ExchangePort", () => {
  const account = encodeUserAccount("0x11");
  const recipient = encodeUserAccount("0x22");
  const asset = ethers.toBeHex(1, 32);
  const liability = ethers.toBeHex(2, 32);
  const debit = encodeAccountAmountBlock(account, liability, 40n);
  const credit = encodeAccountAmountBlock(recipient, asset, 100n);
  const exchange = encodeExchangeBlock(debit, credit);
  let host: Awaited<ReturnType<typeof deploy>>;
  let peer: any;
  beforeEach(async () => {
    const signer = await getSigner(1);
    host = await deploy("TestExchange", await signer.getAddress());
    peer = host.connect(signer);
    await host.seed(account, liability, 80n);
  });
  async function balances() {
    return [await host.balance(account, liability), await host.balance(recipient, asset)];
  }
  it("advertises an unnamed local input schema with one parent per operation and an empty response", async () => {
    const id = await portId(host.interface.getFunction("portExchange")!.selector, host, 0n);
    await expect(host.deploymentTransaction()).to.emit(host, "Endpoint").withArgs(await host.host(), id,
      endpointDescriptor({ input: ExchangeKey, inputHint: 208 }));
    await expect(host.deploymentTransaction()).to.emit(host, "Annotation")
      .withArgs(id, encodeLabelBlock(ethers.ZeroHash, "portExchange"));
    await expect(host.deploymentTransaction()).to.emit(host, "Annotation")
      .withArgs(await host.host(), encodeSchemaBlock(exactSpec(ExchangeKey, 208),
        "#accountAmount as (debit, credit)", ethers.ZeroHash));
    expect(ethers.dataLength(exchange)).to.equal(216);
    expect(await peer.portExchange.staticCall(exchange)).to.equal("0x");
  });
  it("debits the first leg then credits the second for each pair", async () => {
    const receipt = await (await peer.portExchange(concat(exchange, exchange))).wait();
    expect(receipt.logs.map((log: any) => host.interface.parseLog(log)?.name))
      .to.deep.equal(["Debited", "Credited", "Debited", "Credited"]);
    expect(await balances()).to.deep.equal([0n, 200n]);
  });
  it("supports booking both sides to the same account", async () => {
    await peer.portExchange(encodeExchangeBlock(debit, encodeAccountAmountBlock(account, asset, 100n)));
    expect(await host.balance(account, liability)).to.equal(40n);
    expect(await host.balance(account, asset)).to.equal(100n);
  });
  it("requires funds before crediting even when both legs use the same account and asset", async () => {
    await expect(peer.portExchange(encodeExchangeBlock(encodeAccountAmountBlock(account, liability, 81n),
      encodeAccountAmountBlock(account, liability, 100n))))
      .to.be.revertedWithCustomError(host, "InsufficientFunds");
    expect(await balances()).to.deep.equal([80n, 0n]);
  });
  it("accepts empty batches and forwards zero amounts to the hooks", async () => {
    expect(await peer.portExchange.staticCall("0x")).to.equal("0x");
    const tx = peer.portExchange(encodeExchangeBlock(encodeAccountAmountBlock(account, liability, 0n),
      encodeAccountAmountBlock(recipient, asset, 0n)));
    await expect(tx).to.emit(host, "Debited").withArgs(account, liability, 0n);
    await expect(tx).to.emit(host, "Credited").withArgs(recipient, asset, 0n);
  });
  for (const length of [0, 104, 207, 209, 312]) {
    it(`rejects parent payload length ${length} without crossing into the next parent`, async () => {
      const invalid = ExchangeKey + ethers.toBeHex(length, 4).slice(2) + exchange.slice(18);
      await expect(peer.portExchange(concat(exchange, invalid, exchange)))
        .to.be.revertedWithCustomError(host, "InvalidBlock");
      expect(await balances()).to.deep.equal([80n, 0n]);
    });
  }
  for (const length of [7, 8, 112, 215]) {
    it(`rejects a truncated parent of ${length} bytes and rolls back earlier parents`, async () => {
      await expect(peer.portExchange(concat(exchange, ethers.dataSlice(exchange, 0, length))))
        .to.be.revertedWithCustomError(host, length < 8 ? "InvalidBlock" : "OutOfBounds");
      expect(await balances()).to.deep.equal([80n, 0n]);
    });
  }
  it("rejects a wrong parent key and the old unwrapped pairs", async () => {
    for (const invalid of [encodeBlock(Keys.List, concat(debit, credit)), concat(debit, credit)]) {
      await expect(peer.portExchange(invalid)).to.be.revertedWithCustomError(host, "InvalidBlock");
    }
  });
  it("rejects malformed child headers and rolls back the debit", async () => {
    for (const invalid of ["0xffffffff" + credit.slice(10),
      credit.slice(0, 10) + "00000040" + credit.slice(18)]) {
      await expect(peer.portExchange(encodeExchangeBlock(debit, invalid)))
        .to.be.revertedWithCustomError(host, "InvalidBlock");
      expect(await balances()).to.deep.equal([80n, 0n]);
    }
  });
  it("rejects extra children instead of treating them as another operation", async () => {
    await expect(peer.portExchange(concat(exchange, encodeBlock(ExchangeKey, concat(debit, credit, credit)))))
      .to.be.revertedWithCustomError(host, "InvalidBlock");
    expect(await balances()).to.deep.equal([80n, 0n]);
  });
  it("rolls back earlier pairs when a later debit fails", async () => {
    await expect(peer.portExchange(concat(exchange, exchange, exchange)))
      .to.be.revertedWithCustomError(host, "InsufficientFunds");
    expect(await balances()).to.deep.equal([80n, 0n]);
  });
  it("rolls back the debit when the credit overflows", async () => {
    await host.seed(recipient, asset, ethers.MaxUint256);
    let reverted = false;
    try {
      const tx = await peer.portExchange(exchange, { gasLimit: 1_000_000 });
      await tx.wait();
    } catch { reverted = true; }
    expect(reverted).to.equal(true);
    expect(await balances()).to.deep.equal([80n, ethers.MaxUint256]);
  });
  it("rejects untrusted callers", async () => {
    await expect(host.portExchange(exchange)).to.be.revertedWithCustomError(host, "AccessDenied");
  });
});
