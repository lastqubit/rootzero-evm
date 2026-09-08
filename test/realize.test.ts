import { expect } from "chai";
import { ethers } from "ethers";
import { deploy } from "./helpers/setup.js";
import {
  encodeLimitsBlock, concat, encodeHostAccount, encodeQuoteBlock,  encodeAmountBlock, encodeAssetLiabilityBlock, encodeBalanceBlock,
  encodePositionBlock, encodeContextBlock,
} from "./helpers/blocks.js";
import "./helpers/matchers.js";

describe("Realization failure atomicity", () => {
  const asset = ethers.zeroPadValue("0x11", 32);
  const liability = ethers.zeroPadValue("0x22", 32);
  const to = ethers.zeroPadValue("0x33", 32);
  const balance = encodeBalanceBlock(asset, 10n);
  let position: string;
  const positionInput = encodeLimitsBlock(0n, ethers.MaxUint256);
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
    const wrongStates = [balance];
    it("checks each result against its paired limits", async () => {
      const first = encodeLimitsBlock(9n, 8n);
      const second = encodeLimitsBlock(10n, 7n);
      await helper.realize(context(concat(state, state), concat(first, second)));
      expect(await committedState()).to.deep.equal([3n, 3n, 30n, 21n]);
    });

    it("invokes the hook before checking limits", async () => {
      await (await helper.failAt(0n, 2n)).wait();
      await rejectsWithoutChanges(method, state, "0x", "DebtFailure");
    });

    it("rolls back earlier positions when a later counterparty is not the host account", async () => {
      const invalid = encodePositionBlock(asset, 10n, liability, 7n, to);
      await rejectsWithoutChanges(method, concat(state, invalid), concat(input, input), "UnexpectedValue");
    });

    it("rejects QUOTE input and rolls back the hook", async () => {
      await rejectsWithoutChanges(method, state,
        encodeQuoteBlock(asset, 0n, liability, ethers.MaxUint256), "InvalidBlock");
    });

    it("rejects the old ASSET_LIABILITY input shape", async () => {
      await rejectsWithoutChanges(method, state, encodeAssetLiabilityBlock(to, liability), "InvalidBlock");
    });

    it("passes the complete counterparty to the hook and emits its fulfilled result", async () => {
      const [result] = await helper.realize.staticCall(context(
        state, input));
      expect(result).to.equal(encodePositionBlock(asset, 10n, liability, 7n));
    });

    for (const pair of [1, 2]) {
      for (const side of ["asset", "debt"]) {
        it(`rolls back all hooks when position ${pair} violates its ${side} limit`, async () => {
          const invalid = side === "asset"
            ? encodeLimitsBlock(11n, ethers.MaxUint256)
            : encodeLimitsBlock(0n, 6n);
          await rejectsWithoutChanges(method, concat(state, state),
            pair === 1 ? concat(invalid, input) : concat(input, invalid),
            "AmountOutOfRange");
        });
      }

    }

    it("rejects the old two-AMOUNT input shape and rolls back the hook", async () => {
      const legacy = concat(encodeAmountBlock(to, ethers.MaxUint256), encodeAmountBlock(to, 0n));
      await rejectsWithoutChanges(method, state, legacy, "InvalidBlock");
    });

    it("rolls back a completed pair when nonempty state outnumbers input", async () => {
      await rejectsWithoutChanges(method, concat(state, state), input, "OutOfBounds");
    });

    it("rolls back a completed pair when nonempty input outnumbers state", async () => {
      await rejectsWithoutChanges(method, state, concat(input, input), "OutOfBounds");
    });

    for (const wrongState of wrongStates) {
      it(`rejects trailing state type ${wrongState.slice(0, 10)} and rolls back earlier pairs`, async () => {
        await rejectsWithoutChanges(method, concat(state, wrongState), concat(input, input),
          wrongState.length < state.length ? "OutOfBounds" : "InvalidBlock");
      });
    }

    for (const lane of ["state", "input"] as const) {
      for (const defect of ["partial header", "truncated payload", "wrong key", "wrong payload length"] as const) {
        it(`rolls back earlier pairs for a trailing ${lane} block with ${defect}`, async () => {
          const block = lane === "state" ? state : input;
          const malformed = defect === "partial header" ? ethers.dataSlice(block, 0, 7)
            : defect === "truncated payload" ? ethers.dataSlice(block, 0, ethers.dataLength(block) - 1)
            : defect === "wrong key" ? "0xffffffff" + block.slice(10)
            : concat(ethers.dataSlice(block, 0, 4), "0x00000000", ethers.dataSlice(block, 8));
          await rejectsWithoutChanges(method,
            concat(state, lane === "state" ? malformed : state),
            concat(input, lane === "input" ? malformed : input),
            defect === "partial header" || defect === "truncated payload" ? "OutOfBounds" : "InvalidBlock");
        });
      }
    }

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
