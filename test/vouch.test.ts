import { expect } from "chai";
import { ethers } from "ethers";
import { deploy } from "./helpers/setup.js";
import {
  concat, encodeAmountBlock, encodeAssetAmountBlock, encodeBlock, encodeEntityBlock, encodeHostAccount, encodeListBlock,
  encodeStepBlock, encodeTrustBlock, encodeUserAccount, encodeVouchBlock, exactSpec, Keys, pad32,
} from "./helpers/blocks.js";
import "./helpers/matchers.js";

const errors = new ethers.Interface([
  "error Untrusted(bytes32 id)", "error UnexpectedState()", "error InvalidBlock()",
  "error StepFailed(uint256 index, uint256 cmd, bytes err)",
]);

async function revertData(call: Promise<unknown>): Promise<string> {
  try {
    await call;
  } catch (e: any) {
    return e.data ?? e.info?.error?.data;
  }
  throw new Error("expected a revert");
}

describe("Vouch", () => {
  // Opaque asset IDs: representation 0x02, category Asset 0x03.
  const usdc = (0x0203n << 240n) | 0x1001n;
  const dai = (0x0203n << 240n) | 0x1002n;
  const account = encodeUserAccount("0x11");
  let commander: any;
  let consumer: any;
  let vouch: bigint;
  let consume: bigint;
  let settle: bigint;
  let consumerAccount: string;
  let native: string;

  beforeEach(async () => {
    commander = await deploy("TestVouchCommander");
    consumer = await deploy("TestTrustConsumer", await commander.host());
    [vouch, consume, settle] = [await commander.vouchCommandId(), await consumer.consumeId(), await commander.settleCommandId()];
    await commander.setCommand(consume, true);
    for (const id of [usdc, dai]) await commander.setTrusted(pad32(id), true);
    consumerAccount = encodeHostAccount(await consumer.host());
    native = await commander.nativeAsset();
    await commander.seed(account, pad32(usdc), 100n);
    await commander.seed(account, native, 10n);
    await commander.seed(consumerAccount, pad32(dai), 1000n);
  });

  const vouchStep = (budget: bigint, ...ids: bigint[]) =>
    encodeStepBlock(vouch, 0n, encodeVouchBlock(budget, concat(...ids.map(encodeEntityBlock))));
  const flow = (budget = 0n) => concat(
    vouchStep(budget, usdc, dai),
    encodeStepBlock(consume, 0n, encodeAmountBlock(40n)),
    encodeStepBlock(settle, 0n, "0x"),
  );

  it("registers VOUCH input and TRUST output like bootstrap registers BOOTSTRAP and BALANCE", async () => {
    const vouchSpec = (BigInt(Keys.Vouch) << 224n) | (40n << 192n) | (256n << 136n);
    await expect(commander.deploymentTransaction()).to.emitEndpoint(commander)
      .withArgs(vouch, 0n, vouchSpec, exactSpec(Keys.Trust, 32), "vouch");
  });

  it("starts a pipeline with TRUST state that a consumer uses and the commander settles", async () => {
    await (await commander.run(account, flow())).wait();
    expect(await commander.balanceOf(account, pad32(usdc))).eq(60n);
    expect(await commander.balanceOf(account, pad32(dai))).eq(80n);
    expect(await commander.balanceOf(consumerAccount, pad32(usdc))).eq(40n);
    expect(await commander.balanceOf(consumerAccount, pad32(dai))).eq(920n);
    expect(await commander.lastRemaining()).eq(0n);
  });

  it("tops the budget up from the account's native balance only when value falls short", async () => {
    await (await commander.run(account, flow(7n))).wait();
    expect([await commander.balanceOf(account, native), await commander.lastRemaining()]).deep.eq([3n, 7n]);
    // Assigned value covers the budget: no debit, and unused value stays in the budget.
    const funded = concat(encodeStepBlock(vouch, 9n, encodeVouchBlock(5n, concat(encodeEntityBlock(usdc), encodeEntityBlock(dai)))),
      encodeStepBlock(consume, 0n, encodeAmountBlock(1n)), encodeStepBlock(settle, 0n, "0x"));
    await (await commander.run(account, funded, { value: 9n })).wait();
    expect([await commander.balanceOf(account, native), await commander.lastRemaining()]).deep.eq([3n, 9n]);
  });

  it("rejects untrusted IDs at the commander before any external step", async () => {
    await commander.setTrusted(pad32(dai), false);
    expect(await revertData(commander.run.staticCall(account, flow()))).eq(errors.encodeErrorResult("Untrusted", [pad32(dai)]));
  });

  it("starts only from empty state and its TRUST state must be consumed", async () => {
    const unused = vouchStep(0n, usdc);
    expect(await revertData(commander.run.staticCall(account, unused))).eq(errors.encodeErrorResult("UnexpectedState", []));
    const twice = concat(vouchStep(0n, usdc), vouchStep(0n, dai));
    expect(await revertData(commander.run.staticCall(account, twice))).eq(errors.encodeErrorResult("UnexpectedState", []));
  });

  it("lets consumers reject TRUST state that does not fit", async () => {
    const one = concat(vouchStep(0n, usdc), encodeStepBlock(consume, 0n, encodeAmountBlock(1n)), encodeStepBlock(settle, 0n, "0x"));
    const failure = errors.parseError(await revertData(commander.run.staticCall(account, one)))!;
    expect([failure.name, failure.args.index, failure.args.cmd]).deep.eq(["StepFailed", 1n, consume]);
  });

  it("rejects malformed VOUCH input exactly like bootstrap", async () => {
    const id = encodeEntityBlock(usdc);
    for (const input of [
      "0x",
      encodeBlock(Keys.Vouch, pad32(0n)),                                        // no LIST
      encodeBlock(Keys.Vouch, concat(pad32(0n), encodeListBlock(id), "0x01")),   // trailing byte
      concat(encodeVouchBlock(0n, id), encodeVouchBlock(0n, id)),               // two outer blocks
      encodeVouchBlock(0n, encodeTrustBlock(usdc)),                              // TRUST is not a request
      encodeVouchBlock(0n, encodeAssetAmountBlock(pad32(usdc), 1n)),             // wrong item type
      encodeBlock(Keys.Bootstrap, concat(pad32(0n), encodeListBlock(id))),       // wrong outer key
    ]) {
      expect(await revertData(commander.run.staticCall(account, encodeStepBlock(vouch, 0n, input))))
        .eq(errors.encodeErrorResult("InvalidBlock", []));
    }
  });

  it("round trips the budget and ENTITY list through Encoder, Blocks and Executions", async () => {
    const codec = await deploy("TestVouchCodec");
    expect(Array.from(await codec.catalog())).deep.eq([
      (BigInt(Keys.Vouch) << 224n) | (40n << 192n) | (256n << 136n), "uint budget, many #entity as ids",
    ]);
    for (const budget of [0n, 1n, ethers.MaxUint256]) {
      for (const ids of ["0x", concat(encodeEntityBlock(usdc), encodeEntityBlock(dai))]) {
        const input = encodeVouchBlock(budget, ids);
        expect(await codec.create(budget, ids)).eq(input);
        for (const execution of [false, true]) {
          expect(Array.from(await codec.unpack(input, ethers.dataLength(input), execution))).deep.eq([budget, ids, 0n, 0xa5n]);
          const extra = concat(input, encodeEntityBlock(usdc));
          expect(Array.from(await codec.unpack(extra, ethers.dataLength(extra), execution))).deep.eq([budget, ids, 40n, 0xa5n]);
        }
      }
    }
  });

  it("vouches for the chain and Rootzero assets without registry entries", async () => {
    const rootzero = 0x0103n << 240n;
    await commander.seed(consumerAccount, pad32(rootzero), 10n);
    const steps = concat(vouchStep(0n, BigInt(native), rootzero),
      encodeStepBlock(consume, 0n, encodeAmountBlock(3n)), encodeStepBlock(settle, 0n, "0x"));
    await (await commander.run(account, steps)).wait();
    expect([await commander.balanceOf(account, native), await commander.balanceOf(account, pad32(rootzero))]).deep.eq([7n, 6n]);
  });
});
