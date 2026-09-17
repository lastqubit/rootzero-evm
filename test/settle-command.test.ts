import { expect } from "chai";
import { ethers } from "ethers";
import { deploy, getSigner, commandId } from "./helpers/setup.js";
import { encodeLimitsBlock, concat, encodePositionBlock, encodeContextBlock, encodeStepBlock, encodeUserAccount, encodeActionBlock, endpointDescriptor, Keys } from "./helpers/blocks.js";
import "./helpers/matchers.js";

describe("Settle command", () => {
  const account = encodeUserAccount("0x11");
  const asset = ethers.toBeHex(1, 32);
  const liability = ethers.toBeHex(2, 32);
  let host: any;
  beforeEach(async () => {
    host = await deploy("TestSettleCommand");
    await host.seed(account, liability, 40n);
  });

  it("advertises POSITION state, empty input and output, and the Settle action", async () => {
    const id = await commandId("settle(bytes)", host);
    expect(await host.commandId()).to.equal(id);
    const tx = host.deploymentTransaction();
    await expect(tx).to.emit(host, "Endpoint").withArgs(await host.host(), id,
      endpointDescriptor({ state: Keys.Position, stateHint: 160 }));
    await expect(tx).to.emit(host, "Annotation").withArgs(id, encodeActionBlock(3n));
  });

  it("does not expose or authorize the removed book command", async () => {
    expect(host.interface.getFunction("book(bytes)")).to.equal(null);
    const removedId = await commandId("book(bytes)", host);
    await expect(host.run(account, encodePositionBlock(asset, 1n, liability, 1n),
      encodeStepBlock(removedId, 0n, "0x"))).to.be.revertedWithCustomError(host, "AccessDenied");
  });

  for (const memory of [false, true]) {
    describe(memory ? "pipeline memory" : "command calldata", () => {
      async function run(state: string, input = "0x", value = 0n, signer = 0) {
        const target = host.connect(await getSigner(signer));
        return memory
          ? target.run(account, state, encodeStepBlock(await host.commandId(), value, input), { value })
          : target.settle(encodeContextBlock(account, state, input), { value });
      }
      async function balances() {
        return [await host.balance(account, asset), await host.balance(account, liability)];
      }

      it("books exact amounts and returns no state or credit", async () => {
        const state = encodePositionBlock(asset, 100n, liability, 40n);
        if (memory) expect(await host.run.staticCall(account, state,
          encodeStepBlock(await host.commandId(), 0n, "0x"))).to.equal(0n);
        else expect(Array.from(await host.settle.staticCall(encodeContextBlock(account, state, "0x"))))
          .to.deep.equal(["0x", 0n]);
        await expect(run(state)).to.emit(host, "BookCalled").withArgs(account);
        expect(await balances()).to.deep.equal([100n, 0n]);
      });

      it("settles full-width quantities without a uint128 debt cap", async () => {
        const quantity = 1n << 128n;
        await host.seed(account, liability, quantity);
        await run(encodePositionBlock(asset, quantity, liability, quantity));
        expect(await balances()).to.deep.equal([quantity, 40n]);
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

      it("settles a funded account counterparty as well as Rootzero positions", async () => {
        const other = encodeUserAccount("0x22");
        await host.seed(other, asset, 100n);
        await run(encodePositionBlock(asset, 100n, liability, 40n, other), "0x");
        expect(await balances()).to.deep.equal([100n, 0n]);
        expect(await host.balance(other, asset)).to.equal(0n);
        expect(await host.balance(other, liability)).to.equal(40n);
      });

      it("rejects LIMITS input and leaves balances unchanged", async () => {
        await expect(run(encodePositionBlock(asset, 10n, liability, 5n), encodeLimitsBlock(10n, 5n)))
          .to.be.revertedWithCustomError(host, memory ? "UnexpectedInput" : "OutOfBounds");
        expect(await balances()).to.deep.equal([0n, 40n]);
      });

      for (const counterparty of [ethers.toBeHex(1, 32)]) {
        it(`skips account validation for an empty exchange with counterparty ${counterparty}`, async () => {
          await run(concat(encodePositionBlock(asset, 10n, liability, 5n),
            encodePositionBlock(asset, 0n, liability, 0n, counterparty)));
          expect(await balances()).to.deep.equal([10n, 35n]);
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

      it("accepts empty state without booking", async () => {
        const receipt = await (await run("0x")).wait();
        expect(receipt.logs.map((log: any) => log.topics[0]))
          .not.to.include(host.interface.getEvent("BookCalled").topicHash);
        expect(await balances()).to.deep.equal([0n, 40n]);
      });
      it("rejects limits without a position", async () => {
        await expect(run("0x", encodeLimitsBlock(0n, 0n)))
          .to.be.revertedWithCustomError(host, memory ? "UnexpectedInput" : "OutOfBounds");
        expect(await balances()).to.deep.equal([0n, 40n]);
      });
      it("rejects partial limits even when state is empty", async () => {
        await expect(run("0x", "0x01"))
          .to.be.revertedWithCustomError(host, memory ? "UnexpectedInput" : "OutOfBounds");
      });
      it("rejects truncated limits", async () => {
        await expect(run(encodePositionBlock(asset, 1n, liability, 1n), "0x01"))
          .to.be.revertedWithCustomError(host, memory ? "UnexpectedInput" : "OutOfBounds");
      });
      it("rejects a truncated final POSITION and rolls back the batch", async () => {
        const position = encodePositionBlock(asset, 1n, liability, 1n);
        await expect(run(concat(position, ethers.dataSlice(position, 0, 167))))
          .to.be.revertedWithCustomError(host, memory ? "InvalidBlock" : "OutOfBounds");
        expect(await balances()).to.deep.equal([0n, 40n]);
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
      if (memory) it("returns assigned native value without changing settlement quantities", async () => {
        const state = encodePositionBlock(asset, 1n, liability, 1n);
        const input = "0x";
        expect(await host.run.staticCall(account, state,
          encodeStepBlock(await host.commandId(), 7n, input), { value: 11n })).to.equal(11n);
        await run(state, input, 7n);
        expect(await balances()).to.deep.equal([1n, 39n]);
      });
    });
  }
});
