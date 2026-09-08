import { expect } from "chai";
import { ethers } from "ethers";
import { commandId, deploy, hostId } from "./helpers/setup.js";
import {
  encodeLimitsBlock, concat, encodeHostAccount, encodeContextBlock, encodePositionBlock,  encodeStepBlock, encodeUserAccount,
} from "./helpers/blocks.js";
import "./helpers/matchers.js";

describe("Counterparty pipeline", () => {
  const account = encodeUserAccount("0x11");
  const counterparty = encodeUserAccount("0x22");
  const asset = ethers.toBeHex(1n, 32);
  const liability = ethers.toBeHex(2n, 32);
  const limits = encodeLimitsBlock(100n, 40n);

  for (const memory of [false, true]) {
    describe(memory ? "memory settlement" : "calldata settlement", () => {
      let host: Awaited<ReturnType<typeof deploy>>;
      let hostCounterparty: string;
      let state: string;
      let realizeId: bigint;
      let settleId: bigint;
      let bookId: bigint;

      beforeEach(async () => {
        host = await deploy("TestCounterpartyPipeline", memory);
        hostCounterparty = encodeHostAccount(await host.host());
        state = encodePositionBlock(asset, 100n, liability, 40n, hostCounterparty);
        realizeId = await commandId("realize(bytes)", host);
        settleId = await commandId("settle(bytes)", host);
        bookId = await commandId("book(bytes)", host);
        await host.seedHost(asset, 200n);
        await host.seedAccount(account, liability, 80n);
      });

      function steps(input = limits) {
        return concat(encodeStepBlock(realizeId, 0n, input), encodeStepBlock(bookId, 0n, "0x"));
      }

      async function snapshot() {
        return Promise.all([
          host.hostBalance(asset), host.hostBalance(liability),
          host.accountBalance(account, asset), host.accountBalance(account, liability),
          host.accountBalance(counterparty, asset), host.accountBalance(counterparty, liability),
          host.realizations(), host.memorySettlements(),
        ]);
      }

      async function rejectsUnchanged(position: string, input: string, error: string) {
        const before = await snapshot();
        let data: string | undefined;
        try {
          await host.run.staticCall(account, position, input);
        } catch (failure: any) {
          data = failure.data ?? failure.info?.error?.data;
        }
        expect(data, "pipeline must revert with error data").to.be.a("string");
        const wrapper = new ethers.Interface(["error FailedCall(address addr, bytes4 selector, bytes err)"]);
        if (data!.startsWith(wrapper.getError("FailedCall")!.selector)) {
          const failure = wrapper.parseError(data!)!;
          expect(failure.args.addr).to.equal(await host.getAddress());
          expect(failure.args.selector).to.be.oneOf([
            ethers.id("realize(bytes)").slice(0, 10), ethers.id("settle(bytes)").slice(0, 10),
            ethers.id("book(bytes)").slice(0, 10),
          ]);
          data = failure.args.err;
        }
        expect(host.interface.parseError(data!)?.name).to.equal(error);
        let reverted = false;
        try {
          const tx = await host.run(account, position, input, { gasLimit: 5_000_000 });
          await tx.wait();
        } catch {
          reverted = true;
        }
        expect(reverted, "the actual transaction must also revert").to.be.true;
        expect(await snapshot()).to.deep.equal(before);
      }

      it("fulfills the executing host's position and books the result", async () => {
        const result = await host.realize.staticCall(encodeContextBlock(account, state, limits));
        expect(result).to.deep.equal([encodePositionBlock(asset, 100n, liability, 40n), 0n]);
        expect(await host.run.staticCall(account, state, steps())).to.equal(0n);
        await host.run(account, state, steps());
        expect(await snapshot()).to.deep.equal([100n, 40n, 100n, 40n, 0n, 0n, 1n, memory ? 1n : 0n]);
      });

      it("processes multiple positions and limits without losing or duplicating amounts", async () => {
        await host.run(account, concat(state, state), steps(concat(limits, limits)));
        expect(await snapshot()).to.deep.equal([0n, 80n, 200n, 0n, 0n, 0n, 2n, memory ? 1n : 0n]);
      });

      for (const kind of ["Rootzero", "account", "other host account", "host node"]) {
        it(`rejects ${kind} as realization counterparty before changing balances`, async () => {
          const invalid = kind === "Rootzero" ? ethers.ZeroHash : kind === "account" ? counterparty
            : kind === "host node" ? ethers.toBeHex(await host.host(), 32)
            : encodeHostAccount(await hostId("0x0000000000000000000000000000000000000033"));
          await rejectsUnchanged(encodePositionBlock(asset, 100n, liability, 40n, invalid),
            steps(), "UnexpectedValue");
        });
      }

      it("can settle the same host-account position directly when its account is funded", async () => {
        await host.run(account, state, encodeStepBlock(settleId, 0n, encodeLimitsBlock(0n, ethers.MaxUint256)));
        expect(await snapshot()).to.deep.equal([100n, 40n, 100n, 40n, 0n, 0n, 0n, memory ? 1n : 0n]);
      });

      it("rejects zero-counterparty settlement and rolls back prior realization", async () => {
        await rejectsUnchanged(encodePositionBlock(asset, 100n, liability, 40n),
          encodeStepBlock(settleId, 0n, encodeLimitsBlock(0n, ethers.MaxUint256)), "InvalidAccount");
        await rejectsUnchanged(state,
          concat(encodeStepBlock(realizeId, 0n, limits), encodeStepBlock(settleId, 0n, encodeLimitsBlock(0n, ethers.MaxUint256))),
          "InvalidAccount");
      });

      it("uses a host account for settlement on another host when funded there", async () => {
        const remote = encodeHostAccount(await hostId("0x0000000000000000000000000000000000000033"));
        const remoteState = encodePositionBlock(asset, 100n, liability, 40n, remote);
        await rejectsUnchanged(remoteState, encodeStepBlock(settleId, 0n, encodeLimitsBlock(0n, ethers.MaxUint256)), "InsufficientFunds");
        await host.seedAccount(remote, asset, 100n);
        await host.run(account, remoteState, encodeStepBlock(settleId, 0n, encodeLimitsBlock(0n, ethers.MaxUint256)));
        expect(await host.accountBalance(remote, asset)).to.equal(0n);
        expect(await host.accountBalance(remote, liability)).to.equal(40n);
        expect(await host.accountBalance(account, asset)).to.equal(100n);
        expect(await host.realizations()).to.equal(0n);
      });

      it("settles an account counterparty directly through the pipeline", async () => {
        await host.seedAccount(counterparty, asset, 100n);
        const accountState = encodePositionBlock(asset, 100n, liability, 40n, counterparty);
        await host.run(account, accountState, encodeStepBlock(settleId, 0n, encodeLimitsBlock(0n, ethers.MaxUint256)));
        expect(await snapshot()).to.deep.equal([200n, 0n, 100n, 40n, 0n, 40n, 0n, memory ? 1n : 0n]);
      });

      it("rolls back an earlier account settlement when a later counterparty cannot pay", async () => {
        await host.seedAccount(counterparty, asset, 100n);
        const accountState = encodePositionBlock(asset, 100n, liability, 40n, counterparty);
        await rejectsUnchanged(concat(accountState, accountState),
          encodeStepBlock(settleId, 0n, concat(encodeLimitsBlock(0n, ethers.MaxUint256), encodeLimitsBlock(0n, ethers.MaxUint256))), "InsufficientFunds");
      });

      it("rolls back realization and earlier booking when a later liability cannot be paid", async () => {
        const second = encodePositionBlock(asset, 100n, liability, 41n, hostCounterparty);
        const secondLimits = encodeLimitsBlock(100n, 41n);
        await rejectsUnchanged(concat(state, second), steps(concat(limits, secondLimits)), "InsufficientFunds");
      });

      it("rolls back earlier realizations when the host runs out of backing", async () => {
        await rejectsUnchanged(concat(state, state, state), steps(concat(limits, limits, limits)), "InsufficientFunds");
      });

      for (const [label, invalidLimits, error] of [
        ["asset minimum", encodeLimitsBlock(101n, 40n), "AmountOutOfRange"],
        ["debt maximum", encodeLimitsBlock(100n, 39n), "AmountOutOfRange"],
        ["truncated limits", ethers.dataSlice(limits, 0, 71), "OutOfBounds"],
      ]) {
        it(`rolls back backing changes for a later invalid ${label}`, async () => {
          await rejectsUnchanged(concat(state, state), steps(concat(limits, invalidLimits)), error);
        });
      }

      it("rolls back realization if the pipeline ends with an unsettled position", async () => {
        await rejectsUnchanged(state, encodeStepBlock(realizeId, 0n, limits), "UnexpectedState");
      });

      for (const debtOnly of [false, true]) {
        it(`realizes and books a ${debtOnly ? "liability" : "asset"}-only position`, async () => {
          const a = debtOnly ? ethers.ZeroHash : asset;
          const l = debtOnly ? liability : ethers.ZeroHash;
          const amount = debtOnly ? 0n : 100n;
          const debt = debtOnly ? 40n : 0n;
          await host.run(account, encodePositionBlock(a, amount, l, debt, hostCounterparty),
            steps(encodeLimitsBlock(amount, debt)));
          expect(await snapshot()).to.deep.equal([
            200n - amount, debt, amount, 80n - debt, 0n, 0n, 1n, memory ? 1n : 0n,
          ]);
        });
      }
    });
  }
});
