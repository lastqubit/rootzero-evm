import { decodeEndpointLog } from "./helpers/endpoint-logs.js";
import { expect } from "chai";
import { ethers } from "ethers";
import { deploy } from "./helpers/setup.js";
import { concat, encodeBalanceBlock, encodeAssetAmountBlock, encodeContextBlock, encodeStateBlock, encodeInputBlock, encodeOutputBlock, exactSpec, Keys } from "./helpers/blocks.js";
import "./helpers/matchers.js";

describe("Command execution records", () => {
  const account = ethers.id("account"), asset = ethers.id("asset");
  const state = concat(encodeBalanceBlock(asset, 2n), encodeBalanceBlock(asset, 7n));
  const input = concat(encodeAssetAmountBlock(asset, 3n), encodeAssetAmountBlock(asset, 4n));
  const output = concat(encodeBalanceBlock(asset, 5n), encodeBalanceBlock(asset, 11n));
  const record = (id: bigint, mask: number, st: string, inp: string, out: string) => concat(
    "0x04", ethers.toBeHex(id, 32), account, mask & 1 ? encodeStateBlock(st) : "0x",
    mask & 2 ? encodeInputBlock(inp) : "0x", mask & 4 ? encodeOutputBlock(out) : "0x");

  it("uses flags independently of specs and emits exactly one selected record at completion", async () => {
    for (const enabled of [0n, 1n]) for (let mask = 0; mask < 8; mask++) {
      const logs = enabled ? 4n | (BigInt(mask) << 3n) : 0n;
      const helper = await deploy("TestCommandLogs", logs, 195);
      expect((await helper.descriptor()) & ((1n << 160n) - 1n)).eq(33n | (enabled ? 16n | (BigInt(mask) << 1n) : 0n));
      expect((await helper.id() >> 224n) & 255n).eq(195n | logs);
      const deployment = await helper.deploymentTransaction().wait();
      const endpoint = deployment.logs.map(decodeEndpointLog).find((v: ReturnType<typeof decodeEndpointLog>) => v !== null)!;
      expect(endpoint.slice(1, 4)).deep.eq([exactSpec(Keys.Balance,64), exactSpec(Keys.AssetAmount,64), exactSpec(Keys.Balance,64)]);
      for (const empty of [false,true]) {
        const st=empty?"0x":state, inp=empty?"0x":input, out=empty?"0x":output;
        const context=encodeContextBlock(account,st,inp);
        expect(Array.from(await helper.run.staticCall(context,{value:9n}))).deep.eq([out,9n]);
        const receipt=await (await helper.run(context,{value:9n})).wait();
        const logs=receipt.logs.filter((l:any)=>l.topics.length===0);
        expect(logs.map((l:any)=>l.data)).deep.eq(enabled?[record(await helper.id(),mask,st,inp,out)]:[]);
        expect(receipt.logs.length).eq((empty?0:2)+(enabled?1:0));
        if(enabled) expect(receipt.logs.at(-1).data).eq(logs[0].data);
      }
    }
  });

  it("preserves snapshots and zero-copy output through forced growth and later allocations", async () => {
    for (const enabled of [0n,1n]) for(let mask=0;mask<8;mask++) {
      const helper=await deploy("TestCommandLogs",enabled ? 4 | (mask << 3) : 0,0);
      for(const count of [0,1,16]) {
        const st=concat(...Array(count).fill(state)), inp=concat(...Array(count).fill(input)), out=concat(...Array(count).fill(output));
        const context=encodeContextBlock(account,st,inp);
        expect(Array.from(await helper.underallocated.staticCall(context))).deep.eq([out,true]);
        const receipt=await(await helper.underallocated(context)).wait();
        expect(receipt.logs.filter((l:any)=>!l.topics.length).map((l:any)=>l.data)).deep.eq(enabled?[record(await helper.id(),mask,st,inp,out)]:[]);
      }
    }
  });

  it("emits nested execution records before the outer completion record", async () => {
    const helper=await deploy("TestCommandLogs",60,0);
    const nestedState=encodeBalanceBlock(asset,20n), nestedInput=encodeAssetAmountBlock(asset,1n);
    await(await helper.setNested(encodeContextBlock(account,nestedState,nestedInput))).wait();
    const receipt=await(await helper.run(encodeContextBlock(account,state,input))).wait();
    const id=await helper.id();
    expect(receipt.logs.filter((l:any)=>!l.topics.length).map((l:any)=>l.data)).deep.eq([
      record(id,7,nestedState,nestedInput,encodeBalanceBlock(asset,21n)),record(id,7,state,input,output)]);
  });

  it("retains malformed-context, invalid-selection and callback failures", async () => {
    const helper=await deploy("TestCommandLogs",60,0);
    for (const invalid of [8n, 16n, 32n, 56n, 1n << 31n, 1n << 32n, (1n << 32n) | 4n, 256n | 4n])
      await expect(deploy("TestCommandLogs",invalid,0)).revertedWithCustomError(helper,"InvalidSpec");
    await expect(helper.run("0x")).revertedWithCustomError(helper,"InvalidBlock");
    const bad=encodeContextBlock(account,state,concat(encodeAssetAmountBlock(asset,3n),encodeAssetAmountBlock(asset,13n)));
    await expect(helper.run(bad)).revertedWithCustomError(helper,"Rejected");
  });
});
