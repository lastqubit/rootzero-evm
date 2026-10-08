import { expect } from "chai";
import { ethers } from "ethers";
import { deploy } from "./helpers/setup.js";
import { encodeBalanceBlock, encodeBlock, encodeInputBlock, encodeOutputBlock, Keys } from "./helpers/blocks.js";

describe("Execution input logging", () => {
  it("wraps only the selected raw input and preserves execution, allocated output and free memory", async () => {
    const helper = await deploy("TestInputLogs");
    const id = ethers.MaxUint256;
    const expectedOutput = ethers.concat([
      encodeBalanceBlock(ethers.toBeHex(7, 32), 11n), encodeBalanceBlock(ethers.toBeHex(13, 32), 17n),
    ]);
    const streams = ["0x", encodeBalanceBlock(ethers.toBeHex(1, 32), 3n),
      ...[1, 23, 24, 25, 31, 32, 33, 257].map(n => encodeBlock(Keys.Bytes, "0x" + "ab".repeat(n))),
      ethers.concat(Array(16).fill(encodeBalanceBlock(ethers.toBeHex(2, 32), 5n)))];
    for (const mask of [0, 1, 2, 3, 4, 5, 6, 7]) for (const input of streams) {
      const result = await helper.logInput.staticCall(input, id, mask);
      expect(result.afterHash).eq(result.beforeHash);
      expect(result.afterMemory).eq(result.beforeMemory);
      expect(result.output).eq(expectedOutput);
      const receipt = await (await helper.logInput(input, id, mask)).wait();
      expect(receipt.logs.map((l: any) => ({ topics: l.topics, data: l.data }))).deep.eq([{
        topics: [], data: ethers.concat(["0x04", ethers.toBeHex(id, 32), ethers.ZeroHash, mask & 2 ? encodeInputBlock(input) : "0x", mask & 4 ? encodeOutputBlock(expectedOutput) : "0x"]),
      }]);
    }
  });
});
