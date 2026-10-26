import { expect } from "chai";
import { ethers } from "ethers";
import { commandId, deploy, getSigner, hostId } from "./helpers/setup.js";
import {
  concat, encodeAccountBlock, encodeAllowanceBlock, encodeAssetBlock, encodeAssetAmountBlock,
  encodeBalanceBlock, encodeContextBlock, encodeHostAccount, encodeEntityBlock,
  encodePositionBlock, encodeStepBlock, encodeUserAccount, exactSpec, Keys,
} from "./helpers/blocks.js";
import { pipelineRecord, stateRecord, stepRecord } from "./helpers/event-records.js";
import "./helpers/matchers.js";

const asset = ethers.id("logged-asset");
const liability = ethers.id("logged-liability");
const account = encodeUserAccount("0x11");
const dataLogs = (receipt: any) => receipt.logs.filter((log: any) => !log.topics.length).map((log: any) => log.data);

describe("Command operation records", () => {
  let host: any;
  beforeEach(async () => {
    host = await deploy("TestHost", await hostId(await (await getSigner()).getAddress()));
  });

  const authorize = async (...ids: bigint[]) =>
    host.authorize(encodeContextBlock(await host.getAdminAccount(), "0x", concat(...ids.map(encodeEntityBlock))));

  for (const method of ["allowance"]) {
    it(`${method} publishes the Input hint and emits no record for empty and repeated batches`, async () => {
      const id = await commandId(`${method}(bytes)`, host, 2n);
      expect((id >> 224n) & 0x38n).eq(16n);
      const allowance = method === "allowance";
      await expect(host.deploymentTransaction()).emitEndpoint(host).withArgs(id, 0n,
        exactSpec(allowance ? Keys.Allowance : Keys.Asset, allowance ? 96 : 32), 0n);
      const item = allowance ? encodeAllowanceBlock(await host.host(), asset, 0n) : encodeAssetBlock(asset);
      for (const input of ["0x", item, concat(item, item)]) {
        const receipt = await (await host[method](encodeContextBlock(await host.getAdminAccount(), "0x", input))).wait();
        expect(dataLogs(receipt)).deep.eq([]);
      }
    });
  }

  it("payout hints State and Input; pipelines record both for its step", async () => {
    const id = await commandId("payout(bytes)", host);
    await expect(host.deploymentTransaction()).emitEndpoint(host).withArgs(id,
      exactSpec(Keys.Balance, 64), exactSpec(Keys.Account, 32), 0n);
    await authorize(id);
    for (const count of [0, 1, 3]) {
      const state = concat(...Array.from({ length: count }, (_, i) => encodeBalanceBlock(asset, BigInt(i + 1))));
      const input = concat(...Array.from({ length: count }, (_, i) => encodeAccountBlock(encodeUserAccount(ethers.toBeHex(i + 20)))));
      expect(dataLogs(await (await host.payout(encodeContextBlock(account, state, input))).wait())).deep.eq([]);
      const pipeline = await (await host.testPipe(account, state, encodeStepBlock(id, 0n, input))).wait();
      expect(dataLogs(pipeline)).deep.eq([pipelineRecord(account, [id]), stateRecord(0, state), stepRecord(0, 0n, input)]);
    }
  });

  it("realize hints State and Output; pipelines record the obligation and the hook-adjusted result", async () => {
    const id = await commandId("realize(bytes)", host);
    const settle = await commandId("settle(bytes)", host);
    await authorize(id, settle);
    await host.setRealizeFee(3n);
    await host.setRealizeDebtFee(2n);
    for (const count of [0, 2]) {
      const state = concat(...Array(count).fill(encodePositionBlock(asset, 10n, liability, 8n, encodeHostAccount(await host.host()))));
      const output = concat(...Array(count).fill(encodePositionBlock(asset, 7n, liability, 6n)));
      const context = encodeContextBlock(account, state, "0x");
      expect((await host.realize.staticCall(context))[0]).eq(output);
      expect(dataLogs(await (await host.realize(context)).wait())).deep.eq([]);
      const steps = concat(encodeStepBlock(id, 0n, "0x"), encodeStepBlock(settle, 0n, "0x"));
      const pipeline = await (await host.testPipe(account, state, steps)).wait();
      expect(dataLogs(pipeline)).deep.eq([pipelineRecord(account, [id, settle]), stateRecord(0, state), stateRecord(1, output)]);
    }
  });

  for (const method of ["cashout", "settle", "settlePayable"]) {
    it(`${method} emits no record directly; pipelines record its hinted lanes`, async () => {
      const id = await commandId(`${method}(bytes)`, host, method === "settlePayable" ? 1n : 0n);
      const native = await (await deploy("TestUtils")).testToChain();
      await authorize(id);
      for (const count of [0, 1, 3]) {
        const item = method === "cashout" ? encodeBalanceBlock(native, 10n) : encodePositionBlock(asset, 10n, liability, 8n);
        const state = concat(...Array(count).fill(item));
        const receipt = await (await host[method](encodeContextBlock(account, state, "0x"),
          { value: method === "settlePayable" ? BigInt(count * 18) : 0n })).wait();
        expect(dataLogs(receipt)).deep.eq([]);
        if (method !== "settlePayable") {
          const pipeline = await (await host.testPipe(account, state, encodeStepBlock(id, 0n, "0x"))).wait();
          const hooks = (r: any) => r.logs.filter((log: any) => log.topics.length).map((log: any) => ({ topics: log.topics, data: log.data }));
          expect(hooks(pipeline)).deep.eq(hooks(receipt));
          expect(dataLogs(pipeline)).deep.eq(method === "cashout"
            ? [pipelineRecord(account, [id]), stateRecord(0, state)] : [pipelineRecord(account, [id])]);
        }
      }
    });
  }

  it("repay leaves logging to the account hooks", async () => {
    const repay = await deploy("TestRepayCommand");
    await repay.seed(account, liability, 17n);
    const state = encodePositionBlock(asset, 12n, liability, 17n);
    const receipt = await (await repay.repay(encodeContextBlock(account, state, "0x"))).wait();
    expect(dataLogs(receipt)).deep.eq([]);
  });

  it("burn emits no record, including an empty batch", async () => {
    const burn = await deploy("TestBurnHost", await hostId(await (await getSigner()).getAddress()));
    expect((await commandId("burn(bytes)", burn) >> 224n) & 0x38n).eq(8n);
    for (const state of ["0x", encodeBalanceBlock(asset, 25n)]) {
      const receipt = await (await burn.burn(encodeContextBlock(account, state, "0x"))).wait();
      expect(dataLogs(receipt)).deep.eq([]);
    }
  });

  for (const method of ["addPool", "removePool"]) {
    it(`${method} emits no record for whole input pairs`, async () => {
      const pool = await deploy("TestPoolCommands", await hostId(await (await getSigner()).getAddress()));
      const pair = method === "addPool" ? concat(encodeAssetAmountBlock(asset, 3n), encodeAssetAmountBlock(liability, 5n))
        : concat(encodeAssetBlock(asset), encodeAssetBlock(liability));
      for (const input of ["0x", pair, concat(pair, pair)]) {
        const receipt = await (await pool[method](encodeContextBlock(await pool.getAdminAccount(), "0x", input))).wait();
        expect(dataLogs(receipt)).deep.eq([]);
      }
    });
  }
});
