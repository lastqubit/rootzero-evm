import { expect } from "chai";
import { ethers } from "ethers";
import { Category, eventRecord, word } from "./event-records.js";

// Endpoints emit no execution records; only Access records may accompany direct calls.
export async function expectNoExecutionRecords(tx: Promise<any>) {
  const receipt = await (await tx).wait();
  expect(receipt.logs.filter((log: any) => !log.topics.length && Number(ethers.dataSlice(log.data, 0, 1)) !== Category.Access)
    .map((log: any) => log.data)).deep.eq([]);
}

export async function expectAccessLogs(tx: Promise<any>, nodes: bigint[], enabled: boolean) {
  const receipt = await (await tx).wait();
  expect(receipt.logs.map((log: any) => ({ topics: log.topics, data: log.data }))).deep.eq(
    nodes.map(node => ({ topics: [], data: eventRecord(Category.Access, word(node), enabled ? "0x01" : "0x00") }))
  );
}
