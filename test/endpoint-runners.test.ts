import { expect } from "chai";
import { ethers } from "ethers";
import { deploy, queryId } from "./helpers/setup.js";
import { concat, encodeBalanceBlock, encodeAssetAmountBlock, encodeContextBlock, exactSpec, Keys } from "./helpers/blocks.js";
import "./helpers/matchers.js";

describe("Endpoint runner lifecycle", () => {
  const asset = ethers.id("asset"), account = ethers.id("account");
  const state = encodeBalanceBlock(asset, 4n);
  const input = encodeAssetAmountBlock(asset, 3n);
  const output = encodeAssetAmountBlock(asset, 6n);
  it("runs commands, once, admin, ports and guards without records for any hint mask", async () => {
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
          expect(receipt.logs.filter((l: any) => !l.topics.length)).deep.eq([]);
          expect(receipt.logs.length).eq(count);
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
  it("runs admin once with budget settlement and complete consumption", async () => {
    const helper = await deploy("TestEndpointRunners", 7);
    const context = encodeContextBlock(account, state, input);
    expect(Array.from(await helper.adminOnce.staticCall(context, { value: 9n }))).deep.eq([output, 8n]);
    const receipt = await (await helper.adminOnce(context, { value: 9n })).wait();
    expect(receipt.logs.length).eq(1);
    expect(receipt.logs[0].topics.length).eq(1);
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
