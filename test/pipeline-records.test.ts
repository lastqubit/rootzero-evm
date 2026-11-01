import { expect } from "chai";
import { ethers } from "ethers";
import { commandId, deploy, getSigner, hostId } from "./helpers/setup.js";
import {
  concat, encodeAccountBlock, encodeAssetAmountBlock, encodeBalanceBlock, encodeBootstrapBlock,
  encodeContextBlock, encodeEntityBlock, encodePositionBlock, encodeRelayInputBlock, encodeStepBlock,
  encodeAmountBlock, encodePayoutBlock, encodeTrustBlock, encodeUserAccount, encodeUserRecipientBlock, pad32,
} from "./helpers/blocks.js";
import { Category, pipelineRecord, stateRecord, stepRecord } from "./helpers/event-records.js";
import { authorizeCommander, commanderDeadline, deployCommanderPair, deployPayoutHost } from "./helpers/commander-proxy.js";
import "./helpers/matchers.js";

const pipelineCategories: number[] = [Category.Pipeline, Category.Input, Category.State];
const records = (receipt: any) => receipt.logs.filter((log: any) => !log.topics.length).map((log: any) => log.data);
const pipelineRecords = (receipt: any) => records(receipt)
  .filter((data: string) => pipelineCategories.includes(Number(ethers.dataSlice(data, 0, 1))));

describe("Pipeline records", () => {
  const asset = pad32(0x1234n);
  const liability = pad32(0x5678n);
  // Deposits start from TRUST state, as a commander's vouch step would produce.
  const trust = encodeTrustBlock(0x1234n);
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
      createPayout: await commandId("createPayout(bytes)", host),
      hinted: await commandId("hinted(bytes)", await deploy("TestHintedHost", await host.host())),
      realize: await commandId("realize(bytes)", host),
      cashout: await commandId("cashout(bytes)", host),
      settle: await commandId("settle(bytes)", host),
      bank: await commandId("bank(bytes)", host),
      relayBalancePayable: await commandId("relayBalancePayable(bytes)", host, 0x81n),
    };
    await host.authorize(encodeContextBlock(await host.getAdminAccount(), "0x",
      concat(...Object.values(ids).map(encodeEntityBlock))));
  });

  const pipe = async (state: string, steps: string, value = 0n) =>
    (await host.testPipe(account, state, steps, { value })).wait();

  it("emits the Pipeline record for an empty pipeline", async () => {
    expect(records(await pipe("0x", "0x"))).deep.eq([pipelineRecord(account, [])]);
  });

  it("logs a boundary state once when Output feeds a State hint", async () => {
    const payee = encodeAccountBlock(encodeUserAccount(ethers.toBeHex(0xbeef, 20)));
    const steps = concat(encodeStepBlock(ids.deposit, 0n, encodeAmountBlock(7n)),
      encodeStepBlock(ids.hinted, 0n, payee));
    expect(records(await pipe(trust, steps))).deep.eq([
      pipelineRecord(account, [ids.deposit, ids.hinted]),
      stateRecord(1, encodeBalanceBlock(asset, 7n)),
      stepRecord(1, 0n, payee),
    ]);
  });

  it("records a payout once, at the createPayout boundary", async () => {
    const payee = ethers.toBeHex(0xbeef, 20);
    const steps = concat(encodeStepBlock(ids.deposit, 0n, encodeAmountBlock(7n)),
      encodeStepBlock(ids.createPayout, 0n, encodeUserRecipientBlock(payee)),
      encodeStepBlock(ids.withdraw, 0n, "0x"));
    expect(records(await pipe(trust, steps))).deep.eq([
      pipelineRecord(account, [ids.deposit, ids.createPayout, ids.withdraw]),
      stateRecord(1, encodeBalanceBlock(asset, 7n)),
      stateRecord(2, encodePayoutBlock(payee, asset, 7n)),
    ]);
  });

  it("logs initial state and hinted input with step indexes", async () => {
    const state = encodeBalanceBlock(asset, 9n);
    const input = encodeAccountBlock(encodeUserAccount(ethers.toBeHex(0xbeef, 20)));
    expect(records(await pipe(state, encodeStepBlock(ids.hinted, 0n, input)))).deep.eq([
      pipelineRecord(account, [ids.hinted]),
      stateRecord(0, state),
      stepRecord(0, 0n, input),
    ]);
  });

  it("logs nonzero assigned value without unhinted input", async () => {
    const steps = concat(encodeStepBlock(ids.depositPayable, 5n, encodeAmountBlock(5n)),
      encodeStepBlock(ids.bank, 0n, "0x"));
    expect(records(await pipe(trust, steps, 5n))).deep.eq([
      pipelineRecord(account, [ids.depositPayable, ids.bank]),
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

  it("logs nothing for local cashout, whose payout was recorded at creation", async () => {
    const native = await (await deploy("TestUtils")).testToChain();
    const state = encodePayoutBlock(await (await getSigner(1)).getAddress(), native, 3n);
    expect(records(await pipe(state, encodeStepBlock(ids.cashout, 0n, "0x")))).deep.eq([
      pipelineRecord(account, [ids.cashout]),
    ]);
  });

  it("stops the Pipeline record at a handoff; the continuation belongs to the destination", async () => {
    const continuation = encodeStepBlock(ids.withdraw, 0n, "0x");
    const steps = concat(encodeStepBlock(ids.deposit, 0n, encodeAmountBlock(7n)),
      encodeStepBlock(ids.relayBalancePayable, 0n, encodeRelayInputBlock(7n, 9n)), continuation);
    expect(records(await pipe(trust, steps))).deep.eq([
      pipelineRecord(account, [ids.deposit, ids.relayBalancePayable]),
      stateRecord(1, encodeBalanceBlock(asset, 7n)),
    ]);
  });

  it("accepts 64 steps and rejects 65", async () => {
    const step = encodeStepBlock(ids.bank, 0n, "0x");
    const receipt = await pipe("0x", concat(...Array(64).fill(step)));
    expect(records(receipt)).deep.eq([pipelineRecord(account, Array(64).fill(ids.bank))]);
    await expect(host.testPipe(account, "0x", concat(...Array(65).fill(step))))
      .revertedWithCustomError(host, "TooManySteps");
  });

  it("reports an external step failure by index and full command ID", async () => {
    const first = encodeStepBlock(ids.deposit, 0n, encodeAmountBlock(7n));
    const failing = encodeStepBlock(ids.deposit, 0n, "0x12");
    let data: string | undefined;
    try {
      await host.testPipe.staticCall(account, trust, concat(first,
        encodeStepBlock(ids.createPayout, 0n, encodeUserRecipientBlock(await (await getSigner(1)).getAddress())),
        encodeStepBlock(ids.withdraw, 0n, "0x"), failing));
    } catch (error: any) {
      data = error.data ?? error.info?.error?.data;
    }
    const errors = new ethers.Interface(["error StepFailed(uint256 index, uint256 cmd, bytes err)"]);
    const failure = errors.parseError(data!);
    expect(failure?.name).eq("StepFailed");
    expect([failure!.args.index, failure!.args.cmd]).deep.eq([3n, ids.deposit]);
  });

  it("leaves direct endpoint calls unlogged", async () => {
    const receipt = await (await host.deposit(encodeContextBlock(account, trust, encodeAmountBlock(7n)))).wait();
    expect(records(receipt)).deep.eq([]);
  });

  it("records a commander pipeline alongside Balance records", async () => {
    const pair = await deployCommanderPair();
    const user = encodeUserAccount(pair.owner);
    await pair.direct.rootzero("0x", commanderDeadline, { value: ethers.parseEther("1") });
    const native = await pair.direct.nativeAsset();
    const bootstrap = await commandId("bootstrap(bytes)", pair.direct);
    const cashout = await commandId("cashout(bytes)", pair.direct);
    const payout = await deployPayoutHost(pair.direct);
    await authorizeCommander(pair.direct, [bootstrap, cashout, payout]);
    const steps = concat(encodeStepBlock(bootstrap, 0n, encodeBootstrapBlock(0n, encodeAssetAmountBlock(native, 7n))),
      encodeStepBlock(payout, 0n, encodeUserRecipientBlock(pair.owner)),
      encodeStepBlock(cashout, 0n, "0x"));
    const receipt = await (await pair.direct.rootzero(steps, commanderDeadline)).wait();
    // createPayout's Output hint is the only record of the payout; cashout logs nothing.
    expect(pipelineRecords(receipt)).deep.eq([
      pipelineRecord(user, [bootstrap, payout, cashout]),
      stateRecord(2, encodePayoutBlock(pair.owner, native, 7n)),
    ]);
  });

  describe("Logs.step", () => {
    const hint = (flags: number) => BigInt(flags) << 224n;
    const STATE = 8, INPUT = 16, OUTPUT = 32;
    // Every other prefix bit set, so a hint must be read from its own bit.
    const others = hint(0xff ^ (STATE | INPUT | OUTPUT));
    const stream = concat(encodeBalanceBlock(asset, 1n), encodeBalanceBlock(liability, 2n));
    const input = encodeAssetAmountBlock(asset, 3n);
    let harness: any;
    beforeEach(async () => { harness = await deploy("TestPipelineRecords"); });

    const logged = async (index: number, cmd: bigint, prevCmd: bigint, value: bigint) =>
      records(await (await harness.step(index, cmd, prevCmd, stream, value, input)).wait());

    it("emits a State record from the State hint alone", async () => {
      expect(await logged(2, hint(STATE), 0n, 0n)).deep.eq([stateRecord(2, stream)]);
    });

    it("emits a State record from the previous command's Output hint alone", async () => {
      expect(await logged(2, 0n, hint(OUTPUT), 0n)).deep.eq([stateRecord(2, stream)]);
    });

    it("emits one State record when both hints are set", async () => {
      expect(await logged(2, hint(STATE), hint(OUTPUT), 0n)).deep.eq([stateRecord(2, stream)]);
    });

    it("emits a Step record from the Input hint alone", async () => {
      expect(await logged(0, hint(INPUT), 0n, 0n)).deep.eq([stepRecord(0, 0n, input)]);
    });

    it("emits a Step record without input from nonzero value alone", async () => {
      expect(await logged(5, 0n, 0n, 9n)).deep.eq([stepRecord(5, 9n)]);
    });

    it("emits a Step record with value and input when both are present", async () => {
      expect(await logged(63, hint(INPUT), 0n, 1n)).deep.eq([stepRecord(63, 1n, input)]);
    });

    it("emits the State record before the Step record", async () => {
      expect(await logged(1, hint(STATE | INPUT), 0n, 4n)).deep.eq([stateRecord(1, stream), stepRecord(1, 4n, input)]);
    });

    it("emits nothing without a hint or value, whatever the other bits", async () => {
      expect(await logged(1, 0n, 0n, 0n)).deep.eq([]);
      expect(await logged(1, others, others | hint(STATE | INPUT), 0n)).deep.eq([]);
    });

    it("ignores the previous command's other hints and this command's Output hint", async () => {
      expect(await logged(1, hint(OUTPUT), hint(STATE | INPUT), 0n)).deep.eq([]);
    });

    it("restores the stream after logging it in place", async () => {
      expect(await harness.step.staticCall(63, hint(STATE), 0n, stream, 0n, input)).eq(stream);
      expect(await harness.step.staticCall(63, hint(STATE | INPUT), hint(OUTPUT), stream, 7n, input)).eq(stream);
    });

    it("logs the shared empty stream and leaves the zero slot and allocator alone", async () => {
      const [zeroSlot, allocated] = await harness.emptyState.staticCall(4);
      expect([zeroSlot, allocated]).deep.eq([0n, 0n]);
      expect(records(await (await harness.emptyState(4)).wait())).deep.eq([stateRecord(4, "0x")]);
    });
  });
});
