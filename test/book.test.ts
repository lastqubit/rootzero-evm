import { expect } from "chai";
import { ethers } from "ethers";
import { deploy, getSigner, commandId } from "./helpers/setup.js";
import { concat, encodePositionBlock, encodeContextBlock, encodeStepBlock, encodeUserAccount, encodeActionBlock, endpointDescriptor, Keys } from "./helpers/blocks.js";
import "./helpers/matchers.js";

describe("Book", () => {
  const account = encodeUserAccount("0x11");
  const asset = ethers.toBeHex(1, 32);
  const liability = ethers.toBeHex(2, 32);
  let host: any;
  beforeEach(async () => {
    host = await deploy("TestBook");
    await host.seed(account, liability, 40n);
  });

  it("advertises POSITION state, empty input/output, and the Book action", async () => {
    const id = await commandId("book(bytes)", host);
    expect(await host.commandId()).to.equal(id);
    const tx = host.deploymentTransaction();
    await expect(tx).to.emit(host, "Endpoint").withArgs(await host.host(), id,
      endpointDescriptor({ state: Keys.Position, stateHint: 160 }));
    await expect(tx).to.emit(host, "Annotation").withArgs(id, encodeActionBlock(18n));
  });

  for (const memory of [false, true]) {
    describe(memory ? "pipeline memory" : "command calldata", () => {
      async function run(state: string, input = "0x", value = 0n, signer = 0) {
        const target = host.connect(await getSigner(signer));
        return memory
          ? target.run(account, state, encodeStepBlock(await host.commandId(), value, input), { value })
          : target.book(encodeContextBlock(account, state, input), { value });
      }
      async function balances() {
        return [await host.balance(account, asset), await host.balance(account, liability)];
      }

      it("books exact amounts and returns no state or credit", async () => {
        const state = encodePositionBlock(asset, 100n, liability, 40n);
        if (memory) expect(await host.run.staticCall(account, state,
          encodeStepBlock(await host.commandId(), 0n, "0x"))).to.equal(0n);
        else expect(Array.from(await host.book.staticCall(encodeContextBlock(account, state, "0x"))))
          .to.deep.equal(["0x", 0n]);
        await expect(run(state)).to.emit(host, "BookCalled").withArgs(account);
        expect(await balances()).to.deep.equal([100n, 0n]);
      });

      it("books a batch and skips absent sides", async () => {
        await run(concat(encodePositionBlock(asset, 100n, ethers.ZeroHash, 0n),
          encodePositionBlock(ethers.ZeroHash, 0n, liability, 40n)));
        expect(await balances()).to.deep.equal([100n, 0n]);
      });

      it("skips both account hooks for zero amounts", async () => {
        const receipt = await (await run(encodePositionBlock(asset, 0n, liability, 0n))).wait();
        const topics = receipt.logs.map((log: any) => log.topics[0]);
        expect(topics).not.to.include(host.interface.getEvent("DebitCalled").topicHash);
        expect(topics).not.to.include(host.interface.getEvent("CreditCalled").topicHash);
        expect(await balances()).to.deep.equal([0n, 40n]);
      });

      for (const counterparty of [encodeUserAccount("0x22"), ethers.toBeHex(1, 32)]) {
        it(`rejects nonzero counterparty ${counterparty} and rolls back earlier bookings`, async () => {
          await expect(run(concat(encodePositionBlock(asset, 10n, liability, 5n),
            encodePositionBlock(asset, 0n, liability, 0n, counterparty))))
            .to.be.revertedWithCustomError(host, "UnexpectedValue");
          expect(await balances()).to.deep.equal([0n, 40n]);
        });
      }

      it("rolls back the batch if a later liability cannot be debited", async () => {
        await expect(run(concat(encodePositionBlock(asset, 10n, liability, 5n),
          encodePositionBlock(asset, 100n, liability, 40n))))
          .to.be.revertedWithCustomError(host, "InsufficientFunds");
        expect(await balances()).to.deep.equal([0n, 40n]);
      });

      it("debits before crediting even when the asset and liability match", async () => {
        await expect(run(encodePositionBlock(liability, 100n, liability, 41n)))
          .to.be.revertedWithCustomError(host, "InsufficientFunds");
        expect(await balances()).to.deep.equal([0n, 40n]);
      });

      it("accepts empty state", async () => { await run("0x"); });
      it("rejects nonempty input", async () => {
        await expect(run(encodePositionBlock(asset, 1n, liability, 1n), "0x01"))
          .to.be.revertedWithCustomError(host, memory ? "UnexpectedInput" : "OutOfBounds");
      });
      it("rejects malformed POSITION headers", async () => {
        const state = encodePositionBlock(asset, 1n, liability, 1n);
        await expect(run("0xffffffff" + state.slice(10)))
          .to.be.revertedWithCustomError(host, "InvalidBlock");
      });
      it("rejects untrusted callers", async () => {
        await expect(run(encodePositionBlock(asset, 1n, liability, 1n), "0x", 0n, 1))
          .to.be.revertedWithCustomError(host, "AccessDenied");
      });
      if (memory) it("rejects assigned native value", async () => {
        await expect(run(encodePositionBlock(asset, 1n, liability, 1n), "0x", 1n))
          .to.be.revertedWithCustomError(host, "ValueNotAllowed");
      });
    });
  }
});
