import { expect } from "chai";
import { ethers } from "ethers";
import { deploy, getSigner, portId } from "./helpers/setup.js";
import { concat, encodeBlock, encodeBookingBlock, localKey, encodeAccountAmountBlock, encodeUserAccount, endpointSpecs, Keys } from "./helpers/blocks.js";
import "./helpers/matchers.js";

describe("BookPort", () => {
  const account = encodeUserAccount("0x11");
  const recipient = encodeUserAccount("0x22");
  const asset = ethers.toBeHex(1, 32);
  const liability = ethers.toBeHex(2, 32);
  const debit = encodeAccountAmountBlock(account, liability, 40n);
  const credit = encodeAccountAmountBlock(recipient, asset, 100n);
  const value = { from: account, to: recipient, asset, amount: 100n, liability, debt: 40n };
  const booking = encodeBookingBlock(value);
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
  it("advertises BOOKING input and empty output without lane logging", async () => {
    const id = await portId(host.interface.getFunction("portBook")!.selector, host, 0n);
    await expect(host.deploymentTransaction()).to.emitEndpoint(host).withArgs(id,
      ...endpointSpecs({ input: Keys.Booking, inputHint: 192 }));
    await expect(host.deploymentTransaction()).to.emitEndpoint(host)
      .withArgs(id, undefined, undefined, undefined, "portBook");
    expect(ethers.dataLength(booking)).to.equal(200);
    expect(await peer.portBook.staticCall(booking)).to.deep.equal(["0x", 0n]);
  });
  it("debits the first leg then credits the second for each booking", async () => {
    const receipt = await (await peer.portBook(concat(booking, booking))).wait();
    expect(receipt.logs.filter((log: any) => log.topics.length).map((log: any) => host.interface.parseLog(log)?.name))
      .to.deep.equal(["Debited", "Credited", "Debited", "Credited"]);
    expect(receipt.logs.filter((log: any) => !log.topics.length)).deep.eq([]);
    expect(await balances()).to.deep.equal([0n, 200n]);
  });
  it("supports booking both sides to the same account", async () => {
    await peer.portBook(encodeBookingBlock({ ...value, to: account }));
    expect(await host.balance(account, liability)).to.equal(40n);
    expect(await host.balance(account, asset)).to.equal(100n);
  });
  it("requires funds before crediting even when both legs use the same account and asset", async () => {
    await expect(peer.portBook(encodeBookingBlock({ ...value, to: account, asset: liability, debt: 81n })))
      .to.be.revertedWithCustomError(host, "InsufficientFunds");
    expect(await balances()).to.deep.equal([80n, 0n]);
  });
  it("accepts empty batches and skips zero-amount legs", async () => {
    expect(await peer.portBook.staticCall("0x")).to.deep.equal(["0x", 0n]);
    const tx = await peer.portBook(encodeBookingBlock({ ...value, amount: 0n, debt: 0n }));
    expect((await tx.wait()).logs).to.have.length(0);
  });
  for (const length of [1, 7, 8, 103, 104, 168, 199]) {
    it(`rejects an incomplete booking of ${length} bytes and rolls back earlier bookings`, async () => {
      await expect(peer.portBook(concat(booking, ethers.dataSlice(booking, 0, length))))
        .to.be.revertedWithCustomError(host, length < 8 ? "InvalidBlock" : "OutOfBounds");
      expect(await balances()).to.deep.equal([80n, 0n]);
    });
  }
  it("rejects list wrappers and the former custom parent", async () => {
    for (const key of [Keys.List, localKey(1)]) {
      await expect(peer.portBook(encodeBlock(key, booking)))
        .to.be.revertedWithCustomError(host, "InvalidBlock");
      expect(await balances()).to.deep.equal([80n, 0n]);
    }
  });
  it("rejects malformed BOOKING headers before applying either leg", async () => {
    const unfunded = encodeBookingBlock({ ...value, debt: 81n });
    for (const invalid of ["0xffffffff" + unfunded.slice(10),
      unfunded.slice(0, 10) + "000000a0" + unfunded.slice(18)]) {
      await expect(peer.portBook(invalid)).to.be.revertedWithCustomError(host, "InvalidBlock");
      expect(await balances()).to.deep.equal([80n, 0n]);
    }
  });
  it("rejects the former ACCOUNT_AMOUNT pair encoding", async () => {
    await expect(peer.portBook(concat(debit, credit))).to.be.revertedWithCustomError(host, "InvalidBlock");
    expect(await balances()).to.deep.equal([80n, 0n]);
  });
  it("rejects an unmatched final ACCOUNT_AMOUNT block", async () => {
    await expect(peer.portBook(concat(booking, debit)))
      .to.be.revertedWithCustomError(host, "InvalidBlock");
    expect(await balances()).to.deep.equal([80n, 0n]);
  });
  it("rolls back earlier bookings when a later debit fails", async () => {
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
