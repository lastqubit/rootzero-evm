import { expect } from "chai";
import { ethers } from "ethers";
import { deploy } from "./helpers/setup.js";
import { concat, encodeBytesBlock } from "./helpers/blocks.js";

describe("Correlated stream log gas", () => {
  it("compares tagged LOG0 against the previous LOG1 format", async () => {
    const helper = await deploy("TestStreamLogs");
    const id = concat("0x00", ethers.dataSlice(ethers.id("correlation"), 1));
    const rows: { streamBytes: number; topicGas: number; prefixedGas: number; saved: number }[] = [];
    for (const size of [0, 1, 32, 256, 4096]) {
      const data = size ? encodeBytesBlock("0x" + "ab".repeat(size)) : "0x";
      const topicGas = Number(await helper.measure.staticCall(id, data, false));
      const prefixedGas = Number(await helper.measure.staticCall(id, data, true));
      for (const prefixed of [false, true]) {
        const receipt = await (await helper.measure(id, data, prefixed)).wait();
        expect(receipt.logs).to.have.length(1);
        expect(receipt.logs[0].topics).deep.eq(prefixed ? [] : [id]);
        expect(receipt.logs[0].data).eq(prefixed ? concat(id, data) : data);
      }
      expect(prefixedGas).lessThan(topicGas);
      rows.push({ streamBytes: ethers.dataLength(data), topicGas, prefixedGas, saved: topicGas - prefixedGas });
    }
    console.table(rows);
  });
});
