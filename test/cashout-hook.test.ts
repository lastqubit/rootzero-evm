import { expect } from "chai";
import { ethers } from "ethers";
import { deploy, getSigner, getProvider } from "./helpers/setup.js";
import "./helpers/matchers.js";

describe("sendChainAsset", () => {
  let host: any;
  beforeEach(async () => {
    host = await deploy("TestCashoutHook");
    await (await (await getSigner()).sendTransaction({ to: await host.getAddress(), value: 100n })).wait();
  });

  async function fails(addr: string, amount: bigint) {
    const data = await host.pay.staticCall(addr, amount).then(
      () => undefined, (error: any) => error.data ?? error.info?.error?.data,
    );
    expect(data).to.equal(host.interface.encodeErrorResult("SendFailed", []));
    await expect(host.pay(addr, amount, { gasLimit: 500_000 }))
      .to.be.revertedWithCustomError(host, "SendFailed");
  }

  it("pays the recipient address", async () => {
    const recipient = await (await getSigner(1)).getAddress();
    const provider = await getProvider();
    const before = BigInt(await provider.send("eth_getBalance", [recipient, "latest"]));
    const tx = await host.pay(recipient, 17n);
    const receipt = await tx.wait();
    expect(receipt.logs).to.have.length(0);
    expect(BigInt(await provider.send("eth_getBalance", [recipient, "latest"])) - before).to.equal(17n);
    expect(await host.paid()).to.equal(17n);
  });

  for (const mode of [0, 2]) {
    it(`allows recipient callbacks and ignores successful return data (mode ${mode})`, async () => {
      const recipient = await deploy("TestCashoutRecipient", mode);
      await host.pay(await recipient.getAddress(), 25n);
      expect(await recipient.received()).to.equal(25n);
      expect(await recipient.paidDuringCallback()).to.equal(25n);
    });
  }

  it("calls recipients for zero amounts", async () => {
    const recipient = await deploy("TestCashoutRecipient", 0);
    const receipt = await (await host.pay(await recipient.getAddress(), 0n)).wait();
    expect(receipt.logs).to.have.length(0);
    expect(await recipient.calls()).to.equal(1n);
    expect(await recipient.received()).to.equal(0n);
    expect(await host.paid()).to.equal(0n);
  });

  it("rejects the zero address and propagates transfer failure for zero amounts", async () => {
    await expect(host.pay(ethers.ZeroAddress, 0n)).to.be.revertedWithCustomError(host, "ZeroAddress");
    const recipient = await deploy("TestCashoutRecipient", 1);
    await fails(await recipient.getAddress(), 0n);
    expect(await host.paid()).to.equal(0n);
  });

  it("requires no chain-asset or event-emitter inheritance", async () => {
    expect(host.interface.getFunction("chainAsset")).to.equal(null);
    expect(host.interface.getEvent("Activity")).to.equal(null);
    const receipt = await host.deploymentTransaction().wait();
    expect(receipt.logs).to.have.length(0);
  });

  it("wraps large recipient reverts and rolls back prior accounting", async () => {
    const recipient = await deploy("TestCashoutRecipient", 1);
    const addr = await recipient.getAddress();
    await fails(addr, 25n);
    expect(await host.paid()).to.equal(0n);
  });

  it("wraps insufficient native funds and rolls back accounting", async () => {
    const addr = await (await getSigner(1)).getAddress();
    await fails(addr, 101n);
    expect(await host.paid()).to.equal(0n);
  });

  it("rejects the zero address", async () => {
    await expect(host.pay(ethers.ZeroAddress, 1n)).to.be.revertedWithCustomError(host, "ZeroAddress");
    expect(await host.paid()).to.equal(0n);
  });
});
