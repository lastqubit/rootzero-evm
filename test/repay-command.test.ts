import { expect } from "chai";
import { ethers } from "ethers";
import { deploy, getSigner, commandId } from "./helpers/setup.js";
import { concat, encodePositionBlock, encodeContextBlock, encodeStepBlock, encodeUserAccount, encodeActionBlock, endpointDescriptor, Keys } from "./helpers/blocks.js";
import "./helpers/matchers.js";

describe("Repay command", () => {
  const account = encodeUserAccount("0x11");
  const other = encodeUserAccount("0x22");
  const asset = ethers.toBeHex(1, 32);
  const liability = ethers.toBeHex(2, 32);
  let host: any;
  beforeEach(async () => {
    host = await deploy("TestRepayCommand");
    await host.seed(account, liability, 40n);
  });

  it("advertises POSITION to POSITION, empty input, and the Repay action", async () => {
    const id = await commandId("repay(bytes)", host);

    const positionSpec = BigInt(Keys.Position) << 224n | 160n << 136n;
    await expect(host.deploymentTransaction()).to.emit(host, "Endpoint").withArgs(await host.host(), id,
      endpointDescriptor({ state: Keys.Position, stateHint: 160, output: positionSpec }));
    await expect(host.deploymentTransaction()).to.emit(host, "Annotation").withArgs(id, encodeActionBlock(82n));
  });

  describe("calldata command", () => {
    function invoke(state: string, input = "0x", simulate = false, target = host) {
      const fn = target.repay;
      const args = [encodeContextBlock(account, state, input)];
      return simulate ? fn.staticCall(...args) : fn(...args);
    }
    for (const counterparty of [ethers.ZeroHash, other, account]) {
      it(`repays only debt and preserves remaining fields for ${counterparty}`, async () => {
        const state = encodePositionBlock(asset, 100n, liability, 40n, counterparty);
        const result = await invoke(state, "0x", true);
        expect(result[0]).to.equal(encodePositionBlock(asset, 100n, liability, 0n, counterparty));
        expect(result[1]).to.equal(0n);
        await expect(invoke(state)).to.emit(host, "BookCalled").withArgs(account, counterparty,
          counterparty === ethers.ZeroHash ? 0n : 40n, 40n);
        expect(await host.balance(account, asset)).to.equal(0n);
        expect(await host.balance(account, liability)).to.equal(counterparty === account ? 40n : 0n);
        if (counterparty === other) expect(await host.balance(other, liability)).to.equal(40n);
      });
    }
    it("handles batches, zero debt, and full-width quantities", async () => {
      const quantity = 1n << 128n;
      await host.seed(account, liability, quantity);
      const state = concat(encodePositionBlock(asset, 9n, liability, quantity), encodePositionBlock(asset, 7n, liability, 0n, other));
      const result = await invoke(state, "0x", true);
      expect(result[0]).to.equal(concat(encodePositionBlock(asset, 9n, liability, 0n), encodePositionBlock(asset, 7n, liability, 0n, other)));
      await invoke(state);
      expect(await host.balance(account, liability)).to.equal(40n);
    });
    it("skips booking for zero debt and accepts empty state", async () => {
      const receipt = await (await invoke(encodePositionBlock(asset, 100n, liability, 0n, other))).wait();
      expect(receipt.logs.map((log: any) => log.topics[0]))
        .not.to.include(host.interface.getEvent("BookCalled").topicHash);
      expect((await invoke("0x", "0x", true))[0]).to.equal("0x");
    });
    it("rolls back earlier repayments if a later debt fails", async () => {
      await expect(invoke(concat(encodePositionBlock(asset, 100n, liability, 5n, other),
        encodePositionBlock(asset, 100n, liability, 40n)))).to.be.revertedWithCustomError(host, "InsufficientFunds");
      expect(await host.balance(account, liability)).to.equal(40n);
      expect(await host.balance(other, liability)).to.equal(0n);
    });
    it("cannot fund repayment from the untouched asset leg", async () => {
      await expect(invoke(encodePositionBlock(liability, 100n, liability, 41n))).to.be.revertedWithCustomError(host, "InsufficientFunds");
    });
    it("rejects nonempty input and malformed position streams", async () => {
      const state = encodePositionBlock(asset, 100n, liability, 5n);
      await expect(invoke(state, "0x01")).to.be.revertedWithCustomError(host, "OutOfBounds");
      await expect(invoke(concat(state, ethers.dataSlice(state, 0, 167)))).to.be.revertedWithCustomError(host, "OutOfBounds");
      await expect(invoke("0xffffffff" + state.slice(10))).to.be.revertedWithCustomError(host, "InvalidBlock");
      expect(await host.balance(account, liability)).to.equal(40n);
    });
    it("rejects untrusted callers", async () => {
      await expect(invoke(encodePositionBlock(asset, 1n, liability, 1n), "0x", false,
        host.connect(await getSigner(1)))).to.be.revertedWithCustomError(host, "AccessDenied");
    });
  });

  for (const counterparty of [ethers.ZeroHash, other]) it(`composes repay then settle for ${counterparty}`, async () => {
    await host.seed(other, asset, 100n);
    const steps = concat(encodeStepBlock(await commandId("repay(bytes)", host), 0n, "0x"),
      encodeStepBlock(await commandId("settle(bytes)", host), 0n, "0x"));
    await host.run(account, encodePositionBlock(asset, 100n, liability, 40n, counterparty), steps);
    expect(await host.balance(account, asset)).to.equal(100n);
    expect(await host.balance(account, liability)).to.equal(0n);
    if (counterparty === other) {
      expect(await host.balance(other, asset)).to.equal(0n);
      expect(await host.balance(other, liability)).to.equal(40n);
    }
  });
});
