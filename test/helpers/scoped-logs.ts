import { expect } from "chai";
import { ethers } from "ethers";
import { Category, eventRecord, word } from "./event-records.js";
import { commandId, guardId } from "./setup.js";
import { encodeUserAccount, encodeInputBlock } from "./blocks.js";

export async function expectInputLog(tx: Promise<any>, host: any, method: string, input: string, guard = false) {
  const id = await (guard ? guardId(`${method}(bytes)`, host) : commandId(`${method}(bytes)`, host, 2n));
  const receipt = await (await tx).wait();
  expect(receipt.logs.filter((log: any) => log.topics.length || log.data.slice(0, 4) !== ethers.toBeHex(Category.Access, 1)).map((log: any) => ({ topics: log.topics, data: log.data }))).deep.eq([
    { topics: [], data: ethers.concat(["0x04", ethers.toBeHex(id, 32), guard ? encodeUserAccount(receipt.from) : await host.getAdminAccount(), encodeInputBlock(input)]) },
  ]);
}

export async function expectAccessLogs(tx: Promise<any>, nodes: bigint[], enabled: boolean) {
  const receipt = await (await tx).wait();
  expect(receipt.logs.map((log: any) => ({ topics: log.topics, data: log.data }))).deep.eq(
    nodes.map(node => ({ topics: [], data: eventRecord(Category.Access, word(node), enabled ? "0x01" : "0x00") }))
  );
}
