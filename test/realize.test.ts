import { expect } from "chai";
import { ethers } from "ethers";
import { deploy } from "./helpers/setup.js";
import {
  MaxUint128, encodeLimitsBlock, concat, encodeHostAccount, encodeQuoteBlock,  encodeAmountBlock, encodeAssetLiabilityBlock, encodeBalanceBlock,
  encodePositionBlock, encodeContextBlock,
} from "./helpers/blocks.js";
import "./helpers/matchers.js";

describe("Realization failure atomicity", () => {
  const asset = ethers.zeroPadValue("0x11", 32);
  const liability = ethers.zeroPadValue("0x22", 32);
  const to = ethers.zeroPadValue("0x33", 32);
  const balance = encodeBalanceBlock(asset, 10n);
  let position: string;
  const positionInput = "0x";
  const context = (state: string, input: string) => encodeContextBlock(ethers.ZeroHash, state, input);
  let helper: Awaited<ReturnType<typeof deploy>>;

  beforeEach(async () => {
    helper = await deploy("TestRealize");
    position = encodePositionBlock(asset, 10n, liability, 7n, encodeHostAccount(await helper.host()));
    // Establish nonzero committed state so rollback must preserve earlier work.
    await (await helper.realize(context(position, positionInput))).wait();
  });

  async function committedState() {
    return Promise.all([
      helper.assetCalls(), helper.debtCalls(), helper.realizedAssets(), helper.realizedDebts(),
    ]);
  }

  async function rejectsWithoutChanges(method: string, state: string, input: string, error: string) {
    const before = await committedState();
    await expect(helper[method](context(state, input), { gasLimit: 3_000_000 }))
      .to.be.revertedWithCustomError(helper, error);
    expect(await committedState()).to.deep.equal(before);
  }

  describe("realize", () => {
    const method = "realize";
    let state: string;
    beforeEach(() => { state = position; });
    const input = positionInput;
    it("realizes a batch with empty input", async () => {
      await helper.realize(context(concat(state, state), "0x"));
      expect(await committedState()).to.deep.equal([3n, 3n, 30n, 21n]);
    });

    it("passes the complete position to the hook and returns its result", async () => {
      const [result, credit] = await helper.realize.staticCall(context(state, "0x"));
      expect(result).to.equal(encodePositionBlock(asset, 10n, liability, 7n));
      expect(credit).to.equal(0n);
    });

    it("accepts empty state and rejects all nonempty input atomically", async () => {
      expect(await helper.realize.staticCall(context("0x", "0x"))).to.deep.equal(["0x", 0n]);
      for (const input of ["0x01", encodeLimitsBlock(0n, MaxUint128),
        encodeQuoteBlock(asset, 0n, liability, MaxUint128), encodeAssetLiabilityBlock(to, liability),
        concat(encodeAmountBlock(to, 1n), encodeAmountBlock(to, 0n))]) {
        for (const state of ["0x", position, concat(position, position)]) {
          await rejectsWithoutChanges(method, state, input, "OutOfBounds");
        }
      }
    });

    it("rolls back earlier positions if a later counterparty is invalid", async () => {
      await rejectsWithoutChanges(method, concat(state, encodePositionBlock(asset, 10n, liability, 7n, to)),
        "0x", "UnexpectedValue");
    });

    it("rolls back earlier hooks for malformed trailing state", async () => {
      for (const [invalid, error] of [
        [balance, "OutOfBounds"], [ethers.dataSlice(state, 0, 7), "OutOfBounds"],
        [state.slice(0, -2), "OutOfBounds"], ["0xffffffff" + state.slice(10), "InvalidBlock"],
        [state.slice(0, 10) + "00000000" + state.slice(18), "InvalidBlock"],
      ]) await rejectsWithoutChanges(method, concat(state, invalid), "0x", error);
    });

    for (const hook of ["asset", "debt"]) {
      for (const pair of [1, 2]) {
        it(`rolls back the whole batch when the ${hook} hook fails on pair ${pair}`, async () => {
          const failureAt = BigInt(pair + 1); // One pair was committed in beforeEach.
          await (await helper.failAt(hook === "asset" ? failureAt : 0n, hook === "debt" ? failureAt : 0n)).wait();
          let data: string | undefined;
          try {
            await helper[method].staticCall(context(concat(state, state), concat(input, input)));
          } catch (error: any) {
            data = error.data ?? error.info?.error?.data;
          }
          expect(data, "hook must revert").to.be.a("string");
          const failure = helper.interface.parseError(data!);
          expect(failure?.name).to.equal(hook === "asset" ? "AssetFailure" : "DebtFailure");
          // For POSITION, an asset failure observes the preceding debt hook's
          // mutation; a debt failure occurs before the paired asset hook.
          // Committed counters and totals must nevertheless roll back.
          const assets = hook === "debt" ? failureAt - 1n : failureAt;
          const debts = failureAt;
          expect([...failure!.args]).to.deep.equal([assets, debts]);
          await rejectsWithoutChanges(method, concat(state, state), concat(input, input),
            hook === "asset" ? "AssetFailure" : "DebtFailure");
        });
      }
    }
  });
});
