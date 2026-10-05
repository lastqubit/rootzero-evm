import { expect } from "chai";
import { ethers } from "ethers";
import { commandId, guardId } from "./setup.js";
import { encodeInputBlock } from "./blocks.js";

export async function expectInputLog(tx: Promise<any>, host: any, method: string, input: string, guard = false) {
  const id = await (guard ? guardId(`${method}(bytes)`, host) : commandId(`${method}(bytes)`, host, 2n));
  const receipt = await (await tx).wait();
  expect(receipt.logs.map((log: any) => ({ topics: log.topics, data: log.data }))).deep.eq([
    { topics: [], data: ethers.concat([ethers.toBeHex(id, 32), encodeInputBlock(input)]) },
  ]);
}
