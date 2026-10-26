import { expect } from "chai";
import { ethers } from "ethers";
import { Category, eventRecord, word } from "./event-records.js";

// Endpoints emit no execution records; only Trust records may accompany direct calls.
export async function expectNoExecutionRecords(tx: Promise<any>) {
  const receipt = await (await tx).wait();
  expect(receipt.logs.filter((log: any) => !log.topics.length && Number(ethers.dataSlice(log.data, 0, 1)) !== Category.Trust)
    .map((log: any) => log.data)).deep.eq([]);
}

export async function expectTrustLogs(tx: Promise<any>, ids: bigint[], enabled: boolean) {
  const receipt = await (await tx).wait();
  expect(receipt.logs.map((log: any) => ({ topics: log.topics, data: log.data }))).deep.eq(
    ids.map(id => ({ topics: [], data: eventRecord(Category.Trust, word(id), enabled ? "0x01" : "0x00") }))
  );
}
