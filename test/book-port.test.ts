import { expect } from "chai";
import { ethers } from "ethers";
import { deploy, getSigner, portId } from "./helpers/setup.js";
import { concat, encodeBlock, encodeBookPortBlock, BookPortKey, encodeSchemaBlock, exactSpec, encodeAccountAmountBlock, encodeLabelBlock, encodeUserAccount, endpointDescriptor, Keys } from "./helpers/blocks.js";
import "./helpers/matchers.js";

describe("BookPort", () => {
  const account = encodeUserAccount("0x11");
  const recipient = encodeUserAccount("0x22");
  const asset = ethers.toBeHex(1, 32);
  const liability = ethers.toBeHex(2, 32);
  const debit = encodeAccountAmountBlock(account, liability, 40n);
  const credit = encodeAccountAmountBlock(recipient, asset, 100n);
  const booking = encodeBookPortBlock(debit, credit);
  let host: Awaited<ReturnType<typeof deploy>>;
  let peer: any;
  beforeEach(async () => {
    const signer = await getSigner(1);
    host = await deploy("TestBookPort", await signer.getAddress());
    peer = host.connect(signer);
    await host.seed(account, liability, 80n);
  });
  async function balances() {
    return [await host.balance(account, liability), await host.balance(recipient, asset)];
  }
  it("advertises an unnamed local input schema with one parent per operation and an empty response", async () => {
    const id = await portId(host.interface.getFunction("portBook")!.selector, host, 0n);
    await expect(host.deploymentTransaction()).to.emit(host, "Endpoint").withArgs(await host.host(), id,
      endpointDescriptor({ input: BookPortKey, inputHint: 208 }));
    await expect(host.deploymentTransaction()).to.emit(host, "Annotation")
      .withArgs(id, encodeLabelBlock(ethers.ZeroHash, "portBook"));
    await expect(host.deploymentTransaction()).to.emit(host, "Annotation")
      .withArgs(await host.host(), encodeSchemaBlock(exactSpec(BookPortKey, 208),
        "#accountAmount as (debit, credit)", ethers.ZeroHash));
    expect(ethers.dataLength(booking)).to.equal(216);
    expect(await peer.portBook.staticCall(booking)).to.deep.equal(["0x", 0n]);
  });
  it("debits the first leg then credits the second for each pair", async () => {
    const receipt = await (await peer.portBook(concat(booking, booking))).wait();
    expect(receipt.logs.map((log: any) => host.interface.parseLog(log)?.name))
      .to.deep.equal(["Debited", "Credited", "Debited", "Credited"]);
    expect(await balances()).to.deep.equal([0n, 200n]);
  });
  it("supports booking both sides to the same account", async () => {
    await peer.portBook(encodeBookPortBlock(debit, encodeAccountAmountBlock(account, asset, 100n)));
    expect(await host.balance(account, liability)).to.equal(40n);
    expect(await host.balance(account, asset)).to.equal(100n);
  });
  it("requires funds before crediting even when both legs use the same account and asset", async () => {
    await expect(peer.portBook(encodeBookPortBlock(encodeAccountAmountBlock(account, liability, 81n),
      encodeAccountAmountBlock(account, liability, 100n))))
      .to.be.revertedWithCustomError(host, "InsufficientFunds");
    expect(await balances()).to.deep.equal([80n, 0n]);
  });
  it("accepts empty batches and skips zero-amount legs", async () => {
    expect(await peer.portBook.staticCall("0x")).to.deep.equal(["0x", 0n]);
    const tx = await peer.portBook(encodeBookPortBlock(encodeAccountAmountBlock(account, liability, 0n),
      encodeAccountAmountBlock(recipient, asset, 0n)));
    expect((await tx.wait()).logs).to.have.length(0);
  });
  for (const length of [0, 104, 207, 209, 312]) {
    it(`rejects parent payload length ${length} without crossing into the next parent`, async () => {
      const invalid = BookPortKey + ethers.toBeHex(length, 4).slice(2) + booking.slice(18);
      await expect(peer.portBook(concat(booking, invalid, booking)))
        .to.be.revertedWithCustomError(host, "InvalidBlock");
      expect(await balances()).to.deep.equal([80n, 0n]);
    });
  }
  for (const length of [7, 8, 112, 215]) {
    it(`rejects a truncated parent of ${length} bytes and rolls back earlier parents`, async () => {
      await expect(peer.portBook(concat(booking, ethers.dataSlice(booking, 0, length))))
        .to.be.revertedWithCustomError(host, length < 8 ? "InvalidBlock" : "OutOfBounds");
      expect(await balances()).to.deep.equal([80n, 0n]);
    });
  }
  it("rejects a wrong parent key and the old unwrapped pairs", async () => {
    for (const invalid of [encodeBlock(Keys.List, concat(debit, credit)), concat(debit, credit)]) {
      await expect(peer.portBook(invalid)).to.be.revertedWithCustomError(host, "InvalidBlock");
    }
  });
  it("rejects malformed child headers before applying either leg", async () => {
    // This debit would fail if the hook ran before decoding the credit.
    const unfundedDebit = encodeAccountAmountBlock(account, liability, 81n);
    for (const invalid of ["0xffffffff" + credit.slice(10),
      credit.slice(0, 10) + "00000040" + credit.slice(18)]) {
      await expect(peer.portBook(encodeBookPortBlock(unfundedDebit, invalid)))
        .to.be.revertedWithCustomError(host, "InvalidBlock");
      expect(await balances()).to.deep.equal([80n, 0n]);
    }
  });
  it("rejects extra children instead of treating them as another operation", async () => {
    await expect(peer.portBook(concat(booking, encodeBlock(BookPortKey, concat(debit, credit, credit)))))
      .to.be.revertedWithCustomError(host, "InvalidBlock");
    expect(await balances()).to.deep.equal([80n, 0n]);
  });
  it("rolls back earlier pairs when a later debit fails", async () => {
    await expect(peer.portBook(concat(booking, booking, booking)))
      .to.be.revertedWithCustomError(host, "InsufficientFunds");
    expect(await balances()).to.deep.equal([80n, 0n]);
  });
  it("rolls back the debit when the credit overflows", async () => {
    await host.seed(recipient, asset, ethers.MaxUint256);
    let reverted = false;
    try {
      const tx = await peer.portBook(booking, { gasLimit: 1_000_000 });
      await tx.wait();
    } catch { reverted = true; }
    expect(reverted).to.equal(true);
    expect(await balances()).to.deep.equal([80n, ethers.MaxUint256]);
  });
  it("rejects untrusted callers", async () => {
    await expect(host.portBook(booking)).to.be.revertedWithCustomError(host, "AccessDenied");
  });
});
