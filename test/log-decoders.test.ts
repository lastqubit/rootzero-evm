import { expect } from "chai";
import { Contract, Interface, type ContractTransactionResponse } from "ethers";
import "./helpers/matchers.js";
import { decodeBlockLog, decodeBlocks, decodeFixedBlock } from "./helpers/log-blocks.js";

describe("Log decoding and assertions", () => {
  it("rejects incomplete headers, truncated payloads and unexpected fixed-block siblings", () => {
    expect(() => decodeBlocks("0x12345678000000")).to.throw("Truncated block header");
    expect(() => decodeBlocks("0x1234567800000002ff")).to.throw("Truncated block payload");
    const block = "1234567800000001ff";
    expect(decodeFixedBlock("0x" + block, "0x12345678", 1)).eq("0xff");
    expect(() => decodeFixedBlock("0x" + block + block, "0x12345678", 1)).to.throw("Unexpected fixed block");
    expect(() => decodeFixedBlock("0x" + block, "0x12345678", 2)).to.throw("Unexpected fixed block");
    expect(decodeBlocks("0x")).deep.eq([]);
    expect(decodeBlockLog({ topics: [], data: "0x" })).eq(null);
    expect(decodeBlockLog({ topics: ["0x"], data: "0x" + "00".repeat(32) })).eq(null);
  });

  it("matches only logs from the requested emitter and supports argument wildcards", async () => {
    const address = "0x0000000000000000000000000000000000000001";
    const other = "0x0000000000000000000000000000000000000002";
    const abi = new Interface(["event Value(uint amount, uint sequence)"]);
    const contract = new Contract(address, abi);
    const encoded = abi.encodeEventLog(abi.getEvent("Value")!, [7, 9]);
    const transaction = (emitter: string) => ({
      wait: async () => ({ logs: [{ address: emitter, ...encoded }] }),
    }) as unknown as ContractTransactionResponse;
    await expect(transaction(address)).emit(contract, "Value").withArgs(7, undefined);
    let failure: unknown;
    try { await expect(transaction(other)).emit(contract, "Value"); }
    catch (error) { failure = error; }
    expect(failure).to.be.instanceOf(Error);
    expect(String(failure)).contains("found 0 matching records");
  });
});
