import { expect } from "chai";
import { ethers } from "ethers";
import { deploy } from "./helpers/setup.js";
import { encodeContextBlock } from "./helpers/blocks.js";
import "./helpers/matchers.js";

describe("Exact context decoding", () => {
  it("decodes exactly one context and rejects malformed boundaries and children", async () => {
    const helper = await deploy("TestContextExact");
    const account = ethers.toBeHex(123, 32);
    for (const [state, input] of [["0x", "0x"], ["0xaabb", "0xcc"], ["0x", "0xff"]]) {
      const context = encodeContextBlock(account, state, input);
      expect(Array.from(await helper.contextExact(context))).deep.eq([account, state, input]);
      const valid = ethers.getBytes(context);
      const malformed = [ethers.concat([context, "0x00"]), ethers.concat([context, context])];
      for (let length = 0; length < valid.length; length++) malformed.push(ethers.hexlify(valid.slice(0, length)));
      for (const header of [0, 40, 48 + ethers.dataLength(state)]) {
        const badKey = valid.slice();
        badKey[header] ^= 255;
        malformed.push(ethers.hexlify(badKey));
        for (const size of [0, 1, 0xffffffff]) {
          const badLength = valid.slice();
          badLength.set(ethers.getBytes(ethers.toBeHex(size, 4)), header + 4);
          if (ethers.hexlify(badLength) !== context) malformed.push(ethers.hexlify(badLength));
        }
      }
      for (const data of malformed) await expect(helper.contextExact(data)).revertedWithCustomError(helper, "InvalidBlock");
    }
  });

});
