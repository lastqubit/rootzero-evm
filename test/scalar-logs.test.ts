import { expect } from "chai";
import { ethers } from "ethers";
import { deploy } from "./helpers/setup.js";
import { concat, encodeAccountBalanceBlock, encodeBalanceBlock, encodePipelineBlock } from "./helpers/blocks.js";

describe("Temporary scalar logs", () => {
  it("preserves live memory and the allocator across repeated full-width logs", async () => {
    const helper = await deploy("TestStreamLogs");
    for (const codes of [0n, ethers.MaxUint256]) for (const amount of [0n, 1n, ethers.MaxUint256]) {
      const subject = ethers.toBeHex(amount, 32);
      const receipt = await (await helper.emitScalars(codes, subject, amount, "0x" + "ab".repeat(97))).wait();
      const record = (data: string) => ({ topics: [], data: concat(ethers.toBeHex(codes, 32), data) });
      expect(receipt.logs.map((log: any) => ({ topics: [...log.topics], data: log.data }))).deep.eq([
        record(encodePipelineBlock(subject, amount)), record(encodeBalanceBlock(subject, amount)),
        { topics: [], data: concat(ethers.toBeHex(0x20000001n | (2n << 32n), 32), encodeAccountBalanceBlock(subject, subject, amount)) },
        record(encodePipelineBlock(subject, amount)),
      ]);
    }
  });
});
