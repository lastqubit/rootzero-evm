import { expect } from "chai";
import { ethers } from "ethers";
import { commandId, deploy, getSigner, hostId } from "./helpers/setup.js";
import {
  concat, encodeAccountBlock, encodeAllowanceBlock, encodeAssetBlock, encodeAssetAmountBlock,
  encodeBalanceBlock, encodeContextBlock, encodeHostAccount, encodeInputBlock, encodeNodeBlock,
  encodeOutputBlock, encodePipelineBlock, encodePositionBlock, encodeStateBlock, encodeStepBlock, encodeUserAccount,
  exactSpec, Keys,
} from "./helpers/blocks.js";
import "./helpers/matchers.js";

const asset = ethers.id("logged-asset");
const liability = ethers.id("logged-liability");
const account = encodeUserAccount("0x11");
const dataLogs = (receipt: any) => receipt.logs.filter((log: any) => !log.topics.length).map((log: any) => log.data);
const prefixed = (id: bigint, ...blocks: string[]) => concat(ethers.toBeHex(id, 32), ...blocks);

describe("Command operation logs", () => {
  let host: any;
  beforeEach(async () => {
    host = await deploy("TestHost", await hostId(await (await getSigner()).getAddress()));
  });

  for (const method of ["allowAsset", "denyAsset", "allowance"]) {
    it(`${method} publishes host scope and logs complete empty and repeated INPUT batches`, async () => {
      const id = await commandId(`${method}(bytes)`, host, 2n);
      const allowance = method === "allowance";
      const action = allowance ? 2n : method === "allowAsset" ? 20n : 21n;
      const codes = 0x20000002n | (action << 32n) | (allowance ? 0n : (method === "allowAsset" ? 0xa0000001n : 0xa0000000n) << 64n);
      await expect(host.deploymentTransaction()).emitEndpoint(host).withArgs(id, 0n,
        exactSpec(allowance ? Keys.Allowance : Keys.Asset, allowance ? 96 : 32) | codes, 0n);
      const item = allowance ? encodeAllowanceBlock(await host.host(), asset, 0n) : encodeAssetBlock(asset);
      for (const input of ["0x", item, concat(item, item)]) {
        const receipt = await (await host[method](encodeContextBlock(await host.getAdminAccount(), "0x", input))).wait();
        expect(dataLogs(receipt)).deep.eq([prefixed(id, encodeInputBlock(input))]);
        expect(receipt.logs[0].topics).deep.eq([]);
      }
    });
  }

  it("payout logs balances and recipients together before hooks", async () => {
    const id = await commandId("payout(bytes)", host);
    const codes = 0x20000001n | (33n << 32n);
    await expect(host.deploymentTransaction()).emitEndpoint(host).withArgs(id,
      exactSpec(Keys.Balance, 64) | codes, exactSpec(Keys.Account, 32) | codes, 0n);
    for (const count of [0, 1, 3]) {
      const state = concat(...Array.from({ length: count }, (_, i) => encodeBalanceBlock(asset, BigInt(i + 1))));
      const input = concat(...Array.from({ length: count }, (_, i) => encodeAccountBlock(encodeUserAccount(ethers.toBeHex(i + 20)))));
      const receipt = await (await host.payout(encodeContextBlock(account, state, input))).wait();
      expect(dataLogs(receipt)).deep.eq([prefixed(id, encodeStateBlock(state), encodeInputBlock(input))]);
      expect(receipt.logs[0].topics).deep.eq([]);
    }
  });

  it("realize preserves the original obligation and logs the hook-adjusted result", async () => {
    const id = await commandId("realize(bytes)", host);
    await host.setRealizeFee(3n);
    await host.setRealizeDebtFee(2n);
    for (const count of [0, 2]) {
      const state = concat(...Array(count).fill(encodePositionBlock(asset, 10n, liability, 8n, encodeHostAccount(await host.host()))));
      const output = concat(...Array(count).fill(encodePositionBlock(asset, 7n, liability, 6n)));
      const context = encodeContextBlock(account, state, "0x");
      expect((await host.realize.staticCall(context))[0]).eq(output);
      const receipt = await (await host.realize(context)).wait();
      expect(dataLogs(receipt)).deep.eq([prefixed(id, encodeStateBlock(state)), prefixed(id, encodeOutputBlock(output))]);
      expect(receipt.logs[0].topics).deep.eq([]);
      expect(receipt.logs[receipt.logs.length - 1].topics).deep.eq([]);
    }
  });

  for (const method of ["cashout", "settle", "settlePayable"]) {
    it(`${method} preserves its logging policy through direct and optimized execution`, async () => {
      const id = await commandId(`${method}(bytes)`, host, method === "settlePayable" ? 1n : 0n);
      const native = await (await deploy("TestUtils")).testToChain();
      await host.authorize(encodeContextBlock(await host.getAdminAccount(), "0x", encodeNodeBlock(id)));
      for (const count of [0, 1, 3]) {
        const item = method === "cashout" ? encodeBalanceBlock(native, 10n) : encodePositionBlock(asset, 10n, liability, 8n);
        const state = concat(...Array(count).fill(item));
        const receipt = await (await host[method](encodeContextBlock(account, state, "0x"),
          { value: method === "settlePayable" ? BigInt(count * 18) : 0n })).wait();
        expect(dataLogs(receipt)).deep.eq(method === "cashout" ? [prefixed(id, encodeStateBlock(state))] : []);
        if (method === "cashout") expect(receipt.logs[0].topics).deep.eq([]);
        if (method !== "settlePayable") {
          const pipeline = await (await host.testPipe(account, state, encodeStepBlock(id, 0n, "0x"))).wait();
          const records = (r: any) => r.logs.map((log: any) => ({ topics: log.topics, data: log.data }));
          expect(records(pipeline)).deep.eq([
            { topics: [], data: prefixed(0x20000001n, encodePipelineBlock(account, 0n)) },
            ...records(receipt),
          ]);
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

  it("burn logs requested balances, including an empty batch", async () => {
    const burn = await deploy("TestBurnHost", await hostId(await (await getSigner()).getAddress()));
    for (const state of ["0x", encodeBalanceBlock(asset, 25n)]) {
      const receipt = await (await burn.burn(encodeContextBlock(account, state, "0x"))).wait();
      expect(dataLogs(receipt)).deep.eq([prefixed(await commandId("burn(bytes)", burn), encodeStateBlock(state))]);
    }
  });

  for (const method of ["addPool", "removePool"]) {
    it(`${method} logs whole input pairs in one record`, async () => {
      const pool = await deploy("TestPoolCommands", await hostId(await (await getSigner()).getAddress()));
      const pair = method === "addPool" ? concat(encodeAssetAmountBlock(asset, 3n), encodeAssetAmountBlock(liability, 5n))
        : concat(encodeAssetBlock(asset), encodeAssetBlock(liability));
      for (const input of ["0x", pair, concat(pair, pair)]) {
        const receipt = await (await pool[method](encodeContextBlock(await pool.getAdminAccount(), "0x", input))).wait();
        expect(dataLogs(receipt)).deep.eq([prefixed(await commandId(`${method}(bytes)`, pool, 2n), encodeInputBlock(input))]);
      }
    });
  }
});
