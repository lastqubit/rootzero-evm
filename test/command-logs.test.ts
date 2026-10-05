import { decodeEndpointLog } from "./helpers/endpoint-logs.js";
import { expect } from "chai";
import { ethers } from "ethers";
import { deploy } from "./helpers/setup.js";
import { concat, encodeBalanceBlock, encodeAssetAmountBlock, encodeContextBlock, encodeStateBlock, encodeInputBlock, encodeOutputBlock, exactSpec, Keys } from "./helpers/blocks.js";
import "./helpers/matchers.js";

describe("Command runner logs", () => {
  const account = ethers.id("account");
  const asset = ethers.id("asset");
  const state = concat(encodeBalanceBlock(asset, 2n), encodeBalanceBlock(asset, 7n));
  const input = concat(encodeAssetAmountBlock(asset, 3n), encodeAssetAmountBlock(asset, 4n));
  const output = concat(encodeBalanceBlock(asset, 5n), encodeBalanceBlock(asset, 11n));

  it("derives logging from codes, publishes lanes, and combines selected context blocks before callbacks", async () => {
    for (let mask = 0; mask < 8; mask++) {
      const codes = [1n, 1n << 96n, (1n << 128n) - 1n].map((c, i) => mask & (1 << i) ? c : 0n);
      const helper = await deploy("TestCommandLogs", ...codes, 255);
      expect((await helper.descriptor()) & ((1n << 160n) - 1n)).eq(1n | (BigInt(mask) << 1n));
      const deployment = await helper.deploymentTransaction().wait();
      const endpoint = deployment.logs.map(decodeEndpointLog).find((value: bigint[] | null) => value !== null)!;
      expect(endpoint.slice(1)).deep.eq([
        exactSpec(Keys.Balance, 64) | codes[0], exactSpec(Keys.AssetAmount, 64) | codes[1], exactSpec(Keys.Balance, 64) | codes[2],
      ]);
      const prefix = ethers.toBeHex(await helper.id(), 32);
      // Unequal source byte lengths are covered separately by the low-level helper benchmark.
      for (const empty of [false, true]) {
        const st = empty ? "0x" : state, inp = empty ? "0x" : input, out = empty ? "0x" : output;
        const context = encodeContextBlock(account, st, inp);
        expect(Array.from(await helper.run.staticCall(context, { value: 9n }))).deep.eq([out, 9n]);
        const receipt = await (await helper.run(context, { value: 9n })).wait();
        const expected: string[] = [];
        if (mask & 3) expected.push(concat(prefix, mask & 1 ? encodeStateBlock(st) : "0x", mask & 2 ? encodeInputBlock(inp) : "0x"));
        if (mask & 4) expected.push(concat(prefix, encodeOutputBlock(out)));
        expect(receipt.logs.filter((l: any) => l.topics.length === 0).map((l: any) => l.data)).deep.eq(expected);
        expect(receipt.logs).to.have.length((empty ? 0 : 2) + expected.length);
        if (mask & 3) expect(receipt.logs[0].data).eq(expected[0]);
        if (mask & 4) expect(receipt.logs.at(-1).data).eq(expected.at(-1));
      }
    }
  });

  it("logs outer context before nested context and nested output before outer output", async () => {
    const helper = await deploy("TestCommandLogs", 1, 2, 3, 0);
    const prefix = ethers.toBeHex(await helper.id(), 32);
    const nestedState = encodeBalanceBlock(asset, 20n);
    const nestedInput = encodeAssetAmountBlock(asset, 1n);
    await (await helper.setNested(encodeContextBlock(account, nestedState, nestedInput))).wait();
    const receipt = await (await helper.run(encodeContextBlock(account, state, input))).wait();
    const logs = receipt.logs.filter((log: any) => log.topics.length === 0);
    expect(logs.map((log: any) => log.data)).deep.eq(
      [concat(encodeStateBlock(state), encodeInputBlock(input)),
        concat(encodeStateBlock(nestedState), encodeInputBlock(nestedInput)), encodeOutputBlock(encodeBalanceBlock(asset, 21n)), encodeOutputBlock(output)]
        .map(stream => concat(prefix, stream)),
    );
  });

  it("retains malformed-context and callback failures with logging enabled", async () => {
    const helper = await deploy("TestCommandLogs", 1, 2, 3, 0);
    await expect(helper.run("0x")).to.be.revertedWithCustomError(helper, "InvalidBlock");
    const bad = encodeContextBlock(account, state,
      concat(encodeAssetAmountBlock(asset, 3n), encodeAssetAmountBlock(asset, 13n)));
    await expect(helper.run(bad)).to.be.revertedWithCustomError(helper, "Rejected");
  });
});
