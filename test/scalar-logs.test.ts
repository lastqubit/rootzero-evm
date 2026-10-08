import { expect } from "chai";
import { ethers } from "ethers";
import { deploy } from "./helpers/setup.js";
import { Category, eventRecord, word } from "./helpers/event-records.js";

describe("Category scalar logs", () => {
  it("emits exact full-width headers and preserves live memory and allocator state", async () => {
    const helper = await deploy("TestEventCategories");
    for (const value of [0n, 1n, ethers.MaxUint256]) {
      const subject = word(value), n = word(value);
      const receipt = await (await helper.emitScalars(subject, value, "0x" + "ab".repeat(97))).wait();
      expect(receipt.logs.map((l: any) => ({ topics: l.topics, data: l.data }))).deep.eq([
        eventRecord(Category.Access,n,"0x00"),
        eventRecord(Category.Access,n,"0x01"),
        eventRecord(Category.Endpoint,n,n,n,n),
        eventRecord(Category.Balance,subject,subject,n),
        eventRecord(Category.Introduction,n,subject,n),
        eventRecord(Category.Envelope,n,n,subject,subject),
        eventRecord(Category.Resolution,subject,subject,"0x00"),
        eventRecord(Category.Resolution,subject,subject,"0x01"),
      ].map(data => ({topics: [], data})));
    }
  });
});
