import { expect } from "chai";
import { ethers } from "ethers";
import { deploy } from "./helpers/setup.js";
import { concat, encodeBytesBlock } from "./helpers/blocks.js";

describe("Codes and block stream Logs gas", () => {
  it("measures existing memory and direct calldata-copy emission", async () => {
    const helper = await deploy("TestLogs");
    const codes = 80n;
    const rows: { streamBytes: number; logGas: number; memGas: number; copyGas: number }[] = [];
    for (const size of [0, 1, 32, 256, 4096]) {
      const data = size ? encodeBytesBlock("0x" + "ab".repeat(size)) : "0x";
      const memGas = Number(await helper.measureMem.staticCall(codes, data));
      const copyGas = Number(await helper.measureCopy.staticCall(codes, data));
      for (const method of ["measureMem", "measureCopy"]) {
        const receipt = await (await helper[method](codes, data)).wait();
        expect(receipt.logs).to.have.length(1);
        expect(receipt.logs[0].topics).deep.eq([]);
        expect(receipt.logs[0].data).eq(concat(ethers.toBeHex(codes, 32), data));
      }
      const streamBytes = ethers.dataLength(data);
      rows.push({ streamBytes, logGas: 375 + 8 * (32 + streamBytes), memGas, copyGas });
    }
    console.table(rows);
  });
});
