import { expect } from "chai";
import { ethers } from "ethers";
import { deploy } from "./helpers/setup.js";
import { concat, encodeBalanceBlock, encodeAssetAmountBlock, encodeContextBlock, encodeStateBlock, encodeInputBlock, encodeOutputBlock } from "./helpers/blocks.js";
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
          const expected: string[] = [];
          if(i < 3 && (mask & 3)) expected.push(concat(prefix, mask & 1 ? encodeStateBlock(st) : "0x", mask & 2 ? encodeInputBlock(inp) : "0x"));
          if(i >= 3 && (mask & 2)) expected.push(concat(prefix, encodeInputBlock(inp)));
          if(i < 4 && (mask & 4)) expected.push(concat(prefix, encodeOutputBlock(out)));
          expect(receipt.logs.filter((l: any) => !l.topics.length).map((l: any) => l.data)).deep.eq(expected);
          expect(receipt.logs.length).eq(count + expected.length);
          if(expected.length && ((i < 3 && (mask & 3)) || (i >= 3 && (mask & 2)))) expect(receipt.logs[0].data).eq(expected[0]);
          if(i < 4 && (mask & 4)) expect(receipt.logs.at(-1).data).eq(expected.at(-1));
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
  it("rejects logging codes on view query registration", async () => {
    const helper = await deploy("TestQueryCodes", 0, 0);
    for (const codes of [[1,0],[0,1],[1,1]]) {
      await expect(deploy("TestQueryCodes", ...codes)).revertedWithCustomError(helper, "InvalidSpec");
    }
  });
});
