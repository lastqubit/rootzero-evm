import { expect } from "chai";
import { ethers } from "ethers";
import { deploy } from "./helpers/setup.js";
import { Keys, encodeStateBlock, concat, encodeBytesBlock, encodePositionBlock, encodeCodesBlock } from "./helpers/blocks.js";

describe("Correlated stream logs", () => {
  it("wraps ordinary memory and the shared empty value without modifying either", async () => {
    const helper = await deploy("TestStreamLogs");
    for (const sharedEmpty of [false, true]) for (const stream of ["0x", encodeCodesBlock(70n), encodeBytesBlock("0xabcdef")]) {
      const expected = sharedEmpty ? "0x" : stream;
      const args = [123n, Keys.State, stream, sharedEmpty] as const;
      expect(await helper.emitMemoryWrap.staticCall(...args)).eq(expected);
      const receipt = await (await helper.emitMemoryWrap(...args)).wait();
      expect(receipt.logs.slice(0, 2).map((log: any) => ({ topics: log.topics, data: log.data }))).deep.eq(
        Array(2).fill({ topics: [], data: concat(ethers.toBeHex(123n, 32), encodeStateBlock(expected)) }));
      expect(helper.interface.parseLog(receipt.logs[2]).name).eq("Ordinary");
    }
  });

  it("emits exact empty, single and mixed block streams without changing memory", async () => {
    const helper = await deploy("TestStreamLogs");
    const streams = ["0x", encodeCodesBlock(80n), concat(
      encodeBytesBlock("0x123456"),
      encodePositionBlock(ethers.id("asset"), ethers.MaxUint256, ethers.id("liability"), 5n, ethers.id("counterparty")),
      encodeCodesBlock(67n))];
    for (const id of [ethers.ZeroHash, concat("0x00", ethers.dataSlice(ethers.id("correlation"), 1)), ethers.toBeHex((1n << 248n) - 1n, 32)]) {
      for (const stream of streams) for (const sharedEmpty of [false, true]) for (const offset of [0, 3, 32]) {
        const source = concat("0x" + "ab".repeat(offset), stream, "0xcdef");
        const data = sharedEmpty ? "0x" : source;
        const selected = sharedEmpty ? "0x" : stream;
        const args = [id, source, 2, sharedEmpty, sharedEmpty ? 0 : offset, ethers.dataLength(selected)] as const;
        expect(await helper.emitStream.staticCall(...args)).eq(data);
        const receipt = await (await helper.emitStream(...args)).wait();
        expect(receipt.logs).to.have.length(3);
        for (const log of receipt.logs.slice(0, 2)) {
          expect(log.topics).deep.eq([]);
          expect(log.data).eq(concat(id, selected));
        }
        const ordinary = helper.interface.parseLog(receipt.logs[2]);
        expect(ordinary.name).eq("Ordinary");
        expect(ordinary.args[0]).eq(7n);
      }
    }
  });
});
