import { expect } from "chai";
import { ethers } from "ethers";
import { commandId, deploy, getSigner, hostId } from "./helpers/setup.js";
import {
  concat, encodeAccountBlock, encodeAssetAmountBlock, encodeBalanceBlock, encodeBootstrapBlock,
  encodeContextBlock, encodeNodeBlock, encodePositionBlock, encodeRelayInputBlock, encodeStepBlock,
  encodeUserAccount, pad32,
} from "./helpers/blocks.js";
import { Category, pipelineRecord, stateRecord, stepRecord } from "./helpers/event-records.js";
import { authorizeCommander, commanderDeadline, deployCommanderPair } from "./helpers/commander-proxy.js";
import "./helpers/matchers.js";

const pipelineCategories: number[] = [Category.Pipeline, Category.Input, Category.State];
const records = (receipt: any) => receipt.logs.filter((log: any) => !log.topics.length).map((log: any) => log.data);
const pipelineRecords = (receipt: any) => records(receipt)
  .filter((data: string) => pipelineCategories.includes(Number(ethers.dataSlice(data, 0, 1))));

describe("Pipeline records", () => {
  const asset = pad32(0x1234n);
  const liability = pad32(0x5678n);
  let host: any;
  let account: string;
  let ids: Record<string, bigint>;

  beforeEach(async () => {
    host = await deploy("TestHost", await hostId(await (await getSigner()).getAddress()));
    account = encodeUserAccount(await (await getSigner(1)).getAddress());
    ids = {
      deposit: await commandId("deposit(bytes)", host),
      depositPayable: await commandId("depositPayable(bytes)", host, 1n),
      withdraw: await commandId("withdraw(bytes)", host),
      payout: await commandId("payout(bytes)", host),
      realize: await commandId("realize(bytes)", host),
      cashout: await commandId("cashout(bytes)", host),
      settle: await commandId("settle(bytes)", host),
      creditAccount: await commandId("creditAccount(bytes)", host),
      relayBalancePayable: await commandId("relayBalancePayable(bytes)", host, 0x81n),
    };
    await host.authorize(encodeContextBlock(await host.getAdminAccount(), "0x",
      concat(...Object.values(ids).map(encodeNodeBlock))));
  });

  const pipe = async (state: string, steps: string, value = 0n) =>
    (await host.testPipe(account, state, steps, { value })).wait();

  it("emits the Pipeline record for an empty pipeline", async () => {
    expect(records(await pipe("0x", "0x"))).deep.eq([pipelineRecord(account, [])]);
  });

  it("logs a boundary state once when Output feeds a State hint", async () => {
    const steps = concat(encodeStepBlock(ids.deposit, 0n, encodeAssetAmountBlock(asset, 7n)),
      encodeStepBlock(ids.withdraw, 0n, "0x"));
    expect(records(await pipe("0x", steps))).deep.eq([
      pipelineRecord(account, [ids.deposit, ids.withdraw]),
      stateRecord(1, encodeBalanceBlock(asset, 7n)),
    ]);
  });

  it("logs initial state and hinted input with step indexes", async () => {
    const payee = encodeUserAccount(ethers.toBeHex(0xbeef, 20));
    const state = encodeBalanceBlock(asset, 9n);
    const input = encodeAccountBlock(payee);
    expect(records(await pipe(state, encodeStepBlock(ids.payout, 0n, input)))).deep.eq([
      pipelineRecord(account, [ids.payout]),
      stateRecord(0, state),
      stepRecord(0, 0n, input),
    ]);
  });

  it("logs nonzero assigned value without unhinted input", async () => {
    const steps = concat(encodeStepBlock(ids.depositPayable, 5n, encodeAssetAmountBlock(asset, 5n)),
      encodeStepBlock(ids.creditAccount, 0n, "0x"));
    expect(records(await pipe("0x", steps, 5n))).deep.eq([
      pipelineRecord(account, [ids.depositPayable, ids.creditAccount]),
      stepRecord(0, 5n),
      stateRecord(1, encodeBalanceBlock(asset, 5n)),
    ]);
  });

  it("logs State and Output hints of one command at both boundaries", async () => {
    const position = encodePositionBlock(asset, 10n, liability, 4n, await host.hostAccount());
    const realized = encodePositionBlock(asset, 10n, liability, 4n);
    const steps = concat(encodeStepBlock(ids.realize, 0n, "0x"), encodeStepBlock(ids.settle, 0n, "0x"));
    expect(records(await pipe(position, steps))).deep.eq([
      pipelineRecord(account, [ids.realize, ids.settle]),
      stateRecord(0, position),
      stateRecord(1, realized),
    ]);
  });

  it("logs state for local hook execution", async () => {
    const native = await (await deploy("TestUtils")).testToChain();
    const state = encodeBalanceBlock(native, 3n);
    expect(records(await pipe(state, encodeStepBlock(ids.cashout, 0n, "0x")))).deep.eq([
      pipelineRecord(account, [ids.cashout]),
      stateRecord(0, state),
    ]);
  });

  it("stops the Pipeline record at a handoff; the continuation belongs to the destination", async () => {
    const continuation = encodeStepBlock(ids.withdraw, 0n, "0x");
    const steps = concat(encodeStepBlock(ids.deposit, 0n, encodeAssetAmountBlock(asset, 7n)),
      encodeStepBlock(ids.relayBalancePayable, 0n, encodeRelayInputBlock(7n, 9n)), continuation);
    expect(records(await pipe("0x", steps))).deep.eq([
      pipelineRecord(account, [ids.deposit, ids.relayBalancePayable]),
      stateRecord(1, encodeBalanceBlock(asset, 7n)),
    ]);
  });

  it("accepts 64 steps and rejects 65", async () => {
    const step = encodeStepBlock(ids.creditAccount, 0n, "0x");
    const receipt = await pipe("0x", concat(...Array(64).fill(step)));
    expect(records(receipt)).deep.eq([pipelineRecord(account, Array(64).fill(ids.creditAccount))]);
    await expect(host.testPipe(account, "0x", concat(...Array(65).fill(step))))
      .revertedWithCustomError(host, "TooManySteps");
  });

  it("leaves direct endpoint calls unlogged", async () => {
    const receipt = await (await host.deposit(encodeContextBlock(account, "0x", encodeAssetAmountBlock(asset, 7n)))).wait();
    expect(records(receipt)).deep.eq([]);
  });

  it("records a commander pipeline alongside Balance records", async () => {
    const pair = await deployCommanderPair();
    const user = encodeUserAccount(pair.owner);
    await pair.direct.rootzero("0x", commanderDeadline, { value: ethers.parseEther("1") });
    const native = await pair.direct.nativeAsset();
    const bootstrap = await commandId("bootstrap(bytes)", pair.direct);
    const cashout = await commandId("cashout(bytes)", pair.direct);
    await authorizeCommander(pair.direct, [bootstrap, cashout]);
    const steps = concat(encodeStepBlock(bootstrap, 0n, encodeBootstrapBlock(0n, encodeAssetAmountBlock(native, 7n))),
      encodeStepBlock(cashout, 0n, "0x"));
    const receipt = await (await pair.direct.rootzero(steps, commanderDeadline)).wait();
    expect(pipelineRecords(receipt)).deep.eq([
      pipelineRecord(user, [bootstrap, cashout]),
      stateRecord(1, encodeBalanceBlock(native, 7n)),
    ]);
  });

  describe("encoders", () => {
    let harness: any;
    beforeEach(async () => { harness = await deploy("TestPipelineRecords"); });

    it("encodes Step with optional value and input", async () => {
      const input = encodeAssetAmountBlock(asset, 3n);
      for (const [index, value, withInput] of [[0, 0n, true], [5, 9n, false], [63, 1n, true], [3, 0n, false]] as const) {
        const receipt = await (await harness.step(index, value, input, withInput)).wait();
        expect(records(receipt)).deep.eq([stepRecord(index, value, withInput ? input : undefined)]);
      }
    });

    it("encodes State in place and restores the stream", async () => {
      const stream = concat(encodeBalanceBlock(asset, 1n), encodeBalanceBlock(liability, 2n));
      expect(await harness.state.staticCall(stream, 63)).eq(stream);
      expect(records(await (await harness.state(stream, 63)).wait())).deep.eq([stateRecord(63, stream)]);
      const [zeroSlot, allocated] = await harness.emptyState.staticCall(4);
      expect([zeroSlot, allocated]).deep.eq([0n, 0n]);
      expect(records(await (await harness.emptyState(4)).wait())).deep.eq([stateRecord(4, "0x")]);
    });
  });
});
