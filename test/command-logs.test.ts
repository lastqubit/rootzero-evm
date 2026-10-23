import { decodeEndpointLog } from "./helpers/endpoint-logs.js";
import { expect } from "chai";
import { ethers } from "ethers";
import { deploy } from "./helpers/setup.js";
import { concat, encodeBalanceBlock, encodeAssetAmountBlock, encodeContextBlock, exactSpec, Keys } from "./helpers/blocks.js";
import "./helpers/matchers.js";

describe("Command execution without endpoint records", () => {
  const account = ethers.id("account"), asset = ethers.id("asset");
  const state = concat(encodeBalanceBlock(asset, 2n), encodeBalanceBlock(asset, 7n));
  const input = concat(encodeAssetAmountBlock(asset, 3n), encodeAssetAmountBlock(asset, 4n));
  const output = concat(encodeBalanceBlock(asset, 5n), encodeBalanceBlock(asset, 11n));
  const dataLogs = (receipt: any) => receipt.logs.filter((log: any) => !log.topics.length).map((log: any) => log.data);

  it("keeps logging hints in the ID only and emits no execution record", async () => {
    for (let mask = 0; mask < 8; mask++) {
      const hints = BigInt(mask) << 3n;
      const helper = await deploy("TestCommandLogs", hints, 195);
      // Hints leave the descriptor untouched: only the state-source and byte-capacity bits are set.
      expect((await helper.descriptor()) & ((1n << 160n) - 1n)).eq(33n);
      expect((await helper.id() >> 224n) & 255n).eq(195n | hints);
      const deployment = await helper.deploymentTransaction().wait();
      const endpoint = deployment.logs.map(decodeEndpointLog).find((v: ReturnType<typeof decodeEndpointLog>) => v !== null)!;
      expect(endpoint.slice(1, 4)).deep.eq([exactSpec(Keys.Balance, 64), exactSpec(Keys.AssetAmount, 64), exactSpec(Keys.Balance, 64)]);
      for (const empty of [false, true]) {
        const context = encodeContextBlock(account, empty ? "0x" : state, empty ? "0x" : input);
        expect(Array.from(await helper.run.staticCall(context, { value: 9n }))).deep.eq([empty ? "0x" : output, 9n]);
        const receipt = await (await helper.run(context, { value: 9n })).wait();
        expect(dataLogs(receipt)).deep.eq([]);
        expect(receipt.logs.length).eq(empty ? 0 : 2);
      }
    }
  });

  it("returns zero-copy output through forced growth and later allocations", async () => {
    const helper = await deploy("TestCommandLogs", 0, 0);
    for (const count of [0, 1, 16]) {
      const context = encodeContextBlock(account, concat(...Array(count).fill(state)), concat(...Array(count).fill(input)));
      expect(Array.from(await helper.underallocated.staticCall(context))).deep.eq([concat(...Array(count).fill(output)), true]);
      expect(dataLogs(await (await helper.underallocated(context)).wait())).deep.eq([]);
    }
  });

  it("runs nested commands without records", async () => {
    const helper = await deploy("TestCommandLogs", 56, 0);
    await (await helper.setNested(encodeContextBlock(account, encodeBalanceBlock(asset, 20n), encodeAssetAmountBlock(asset, 1n)))).wait();
    const receipt = await (await helper.run(encodeContextBlock(account, state, input))).wait();
    expect(dataLogs(receipt)).deep.eq([]);
    expect(receipt.logs.length).eq(3);
  });

  it("rejects flags beyond one byte and retains malformed-context and callback failures", async () => {
    const helper = await deploy("TestCommandLogs", 56, 0);
    for (const invalid of [256n, 1n << 31n, 1n << 32n, (1n << 32n) | 4n, 256n | 4n])
      await expect(deploy("TestCommandLogs", invalid, 0)).revertedWithCustomError(helper, "InvalidSpec");
    await expect(helper.run("0x")).revertedWithCustomError(helper, "InvalidBlock");
    const bad = encodeContextBlock(account, state, concat(encodeAssetAmountBlock(asset, 3n), encodeAssetAmountBlock(asset, 13n)));
    await expect(helper.run(bad)).revertedWithCustomError(helper, "Rejected");
  });
});
