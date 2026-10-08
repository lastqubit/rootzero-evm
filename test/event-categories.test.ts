import { expect } from "chai";
import { ethers } from "ethers";
import { deploy } from "./helpers/setup.js";
import { encodeBlock, encodeLabelBlock, encodeSchemaBlock, exactSpec, Keys } from "./helpers/blocks.js";
import { Category, categoryPayload, eventRecord, word } from "./helpers/event-records.js";
import { decodeEndpointLog } from "./helpers/endpoint-logs.js";
import { decodeMetadataLog } from "./helpers/metadata-logs.js";
import { decodeResolutionLog } from "./helpers/resolution-logs.js";

describe("Event category framing", () => {
  it("preserves repeated empty, unaligned and multi-block metadata without allocating or mutating live bytes", async () => {
    const helper = await deploy("TestEventCategories");
    const batches = ["0x", ...[0,1,31,32,33,257].map(n => encodeBlock(Keys.Bytes,"0x"+"ab".repeat(n))),
      ethers.concat([encodeLabelBlock(ethers.ZeroHash,"name"),encodeSchemaBlock(exactSpec(Keys.Balance,64),"bytes32 asset, uint amount")])];
    for (const data of batches) for (const shared of [false,true]) {
      const actual = shared ? "0x" : data;
      expect(await helper.publish.staticCall(ethers.MaxUint256,data,shared)).eq(actual);
      const receipt = await (await helper.publish(ethers.MaxUint256,data,shared)).wait();
      const expected = eventRecord(Category.Metadata,word(ethers.MaxUint256),actual);
      expect(receipt.logs.map((l:any)=>l.data)).deep.eq([expected,expected]);
      expect(decodeMetadataLog(receipt.logs[0])).deep.eq([{entity:ethers.MaxUint256,data:actual}]);
    }
  });
  it("skips unknown categories and rejects malformed known headers", () => {
    const unknown = {topics:[],data:eventRecord(255,word(0))};
    expect(decodeEndpointLog(unknown)).eq(null);
    expect(decodeMetadataLog(unknown)).deep.eq([]);
    expect(categoryPayload({topics:[],data:"0x"},Category.Execution)).eq(null);
    expect(() => decodeEndpointLog({topics:[],data:eventRecord(Category.Endpoint)})).throws("length");
    expect(() => decodeMetadataLog({topics:[],data:eventRecord(Category.Metadata)})).throws("Truncated");
    expect(() => decodeResolutionLog({topics:[],data:eventRecord(Category.Resolution,word(0),word(0),"0x02")})).throws("status");
  });
});
