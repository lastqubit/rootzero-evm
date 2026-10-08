import { expect } from "chai";
import { ethers } from "ethers";
import { deploy } from "./helpers/setup.js";
import { concat, encodeAccountBalanceBlock, encodeBytesBlock, encodeAmountBlock, encodePositionBlock } from "./helpers/blocks.js";

const codes = [0n, 80n, ethers.MaxUint256, BigInt("0x21" + "00".repeat(31))];
const streams = ["0x", encodeAmountBlock(0n), concat(encodeBytesBlock("0xabcdef"),
  encodePositionBlock(ethers.id("asset"), ethers.MaxUint256, ethers.id("liability"), 5n, ethers.id("counterparty")))];
function checkLogs(logs: any[], stream: string) {
  expect(logs).to.have.length(codes.length);
  logs.forEach((log, i) => {
    expect(log.topics).deep.eq([]);
    expect(log.data).eq(concat(ethers.toBeHex(codes[i], 32), stream));
  });
}

describe("Balance events and historical stream primitives", () => {
  it("balance emits a fixed category header with the actual account balance", async () => {
    const helper = await deploy("TestLogs");
    for (const asset of [ethers.ZeroHash, ethers.id("asset")])
      for (const amount of [0n, (1n << 96n) - 1n, 1n << 96n, ethers.MaxUint256])
        for (const account of [ethers.ZeroHash, ethers.id("account")]) {
          const receipt = await (await helper.emitBalance(account, asset, amount)).wait();
          expect(receipt.logs).to.have.length(1);
          expect(receipt.logs[0].topics).deep.eq([]);
          expect(receipt.logs[0].data).eq(concat("0x07", account, asset, ethers.toBeHex(amount, 32)));
          expect(ethers.dataLength(receipt.logs[0].data)).eq(97);
        }
  });

  it("mem restores preceding words, lengths, payload and allocator state for aligned and unaligned ranges", async () => {
    const helper = await deploy("TestLogs");
    for (const stream of streams) for (const offset of [0, 3, 32]) {
      const data = concat("0x" + "ab".repeat(offset), stream, "0xcdef");
      const args = [codes, data, offset, ethers.dataLength(stream), false] as const;
      expect(await helper.memoryLogs.staticCall(...args)).eq(data);
      checkLogs((await (await helper.memoryLogs(...args)).wait()).logs, stream);
    }
    const args = [codes, "0x", 0, 0, true] as const;
    expect(await helper.memoryLogs.staticCall(...args)).eq("0x");
    checkLogs((await (await helper.memoryLogs(...args)).wait()).logs, "0x");
  });

  it("copy selects exact calldata ranges and preserves allocated memory and subsequent allocations", async () => {
    const helper = await deploy("TestLogs");
    for (const stream of streams) for (const offset of [0, 3, 32]) {
      const data = concat("0x" + "ab".repeat(offset), stream, "0xcdef");
      const args = [codes, data, offset, ethers.dataLength(stream)] as const;
      const result = await helper.calldataLogs.staticCall(...args);
      const abi = ethers.AbiCoder.defaultAbiCoder();
      expect(result.guard).eq(abi.encode(["uint256", "bytes32"], [0x1234, ethers.toBeHex(ethers.MaxUint256, 32)]));
      expect(result.afterLog).eq(abi.encode(["uint256", "bytes"], [0x5678, data]));
      checkLogs((await (await helper.calldataLogs(...args)).wait()).logs, stream);
    }
  });
});
