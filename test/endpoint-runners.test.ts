import { expect } from "chai";
import { ethers } from "ethers";
import { deploy, queryId } from "./helpers/setup.js";
import { concat, encodeUserAccount, encodeBalanceBlock, encodeAssetAmountBlock, encodeContextBlock, encodeStateBlock, encodeInputBlock, encodeOutputBlock, exactSpec, Keys } from "./helpers/blocks.js";
import "./helpers/matchers.js";

describe("Endpoint runner lifecycle", () => {
  const asset = ethers.id("asset"), account = ethers.id("account");
  const state = encodeBalanceBlock(asset, 4n);
  const input = encodeAssetAmountBlock(asset, 3n);
  const output = encodeAssetAmountBlock(asset, 6n);
  it("logs each selected lane for commands, once, admin, ports and guards", async () => {
    for (let mask = 0; mask < 8; mask++) {
      const helper = await deploy("TestEndpointRunners", mask);
      for (const [i, name] of ["batch", "once", "admin", "peer", "protect"].entries()) {
        for (const count of (name === "once" ? [1] : [0, 2])) {
          const st = concat(...Array(count).fill(state));
          const inp = concat(...Array(count).fill(input));
          const out = concat(...Array(count).fill(output));
          const arg = i < 3 ? encodeContextBlock(account, st, inp) : inp;
          const opts = i === 4 ? {} : { value: 9n };
          if(i !== 4) expect(Array.from(await helper.getFunction(name).staticCall(arg, opts))).deep.eq([out, 9n - BigInt(count)]);
          const receipt = await (await helper.getFunction(name)(arg, opts)).wait();
          const prefix = ethers.toBeHex(await helper.ids(i), 32);
          const expected = [concat("0x04", prefix, i < 3 ? account : i === 4 ? encodeUserAccount(receipt.from) : ethers.ZeroHash,
            i < 3 && (mask & 1) ? encodeStateBlock(st) : "0x",
            mask & 2 ? encodeInputBlock(inp) : "0x",
            i < 4 && (mask & 4) ? encodeOutputBlock(out) : "0x")];
          expect(receipt.logs.filter((l: any) => !l.topics.length).map((l: any) => l.data)).deep.eq(expected);
          expect(receipt.logs.length).eq(count + 1);
          expect(receipt.logs.at(-1).data).eq(expected[0]);
        }
      }
      expect(await helper.read(concat(input, input))).eq(concat(output, output));
      expect(await helper.read("0x")).eq("0x");
    }
  });
  it("keeps one-shot consumption checks, admin authorization and callback errors", async () => {
    const helper = await deploy("TestEndpointRunners", 7);
    await expect(helper.getFunction("once")(encodeContextBlock(account, concat(state,state), concat(input,input)), {value: 9n})).revertedWithCustomError(helper,"UnconsumedData");
    await expect(helper.admin(encodeContextBlock(ethers.ZeroHash,"0x","0x"))).revertedWithCustomError(helper,"Rejected");
    const bad = encodeAssetAmountBlock(asset,13n);
    for (const name of ["batch","once","admin"]) await expect(helper.getFunction(name)(encodeContextBlock(account,state,bad),{value: 9n})).revertedWithCustomError(helper,"Rejected");
    await expect(helper.peer(bad,{value: 9n})).revertedWithCustomError(helper,"Rejected");
    await expect(helper.protect(bad)).revertedWithCustomError(helper,"Rejected");
  });
  it("runs admin once with logging, budget settlement and complete consumption", async () => {
    const helper = await deploy("TestEndpointRunners", 7);
    const context = encodeContextBlock(account, state, input);
    expect(Array.from(await helper.adminOnce.staticCall(context, { value: 9n }))).deep.eq([output, 8n]);
    const receipt = await (await helper.adminOnce(context, { value: 9n })).wait();
    const prefix = ethers.toBeHex(await helper.ids(6), 32);
    expect(receipt.logs.length).eq(2);
    expect(receipt.logs[1].data).eq(concat("0x04", prefix, account, encodeStateBlock(state), encodeInputBlock(input), encodeOutputBlock(output)));
    await expect(helper.adminOnce(encodeContextBlock(ethers.ZeroHash, "0x", "0x")))
      .revertedWithCustomError(helper, "Rejected");
    // An authorized empty context still invokes the callback, which requires a balance.
    await expect(helper.adminOnce(encodeContextBlock(account, "0x", "0x")))
      .revertedWithCustomError(helper, "InvalidBlock");
    await expect(helper.adminOnce(encodeContextBlock(account, concat(state, state), concat(input, input)), { value: 9n }))
      .revertedWithCustomError(helper, "UnconsumedData");
    await expect(helper.adminOnce(encodeContextBlock(account, state, encodeAssetAmountBlock(asset, 13n)), { value: 9n }))
      .revertedWithCustomError(helper, "Rejected");
  });
  it("allows explicit port attribution without inferring it from the peer", async () => {
    const helper = await deploy("TestEndpointRunners", 6);
    const receipt = await (await helper.attributedPeer(account, input, {value: 1n})).wait();
    expect(receipt.logs.at(-1).data).eq(concat("0x04", ethers.toBeHex(await helper.ids(3),32), account, encodeInputBlock(input), encodeOutputBlock(output)));
  });
  it("preserves lane keys in view query registration without adding logging flags", async () => {
    const spec = exactSpec(Keys.AssetAmount, 64);
    for (const [inputKey, outputKey] of [[0n, 0n], [1n, 0n], [0n, 1n], [0xffffffffn, 0xffffffffn]]) {
      const helper = await deploy("TestQueryLanes", inputKey, outputKey);
      await expect(helper.deploymentTransaction()).to.emitEndpoint(helper).withArgs(
        await queryId("read(bytes)", helper), 0n, spec | inputKey, spec | outputKey, "read",
      );
    }
  });
  it("rejects reserved bits on view query registration", async () => {
    const helper = await deploy("TestQueryLanes", 0, 0);
    for (const bit of [32n, 64n, 127n, 128n, 135n]) {
      for (const lanes of [[1n << bit, 0n], [0n, 1n << bit]]) {
        await expect(deploy("TestQueryLanes", ...lanes)).revertedWithCustomError(helper, "InvalidSpec");
      }
    }
  });
});
