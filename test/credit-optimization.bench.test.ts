import { expect } from "chai";
import { ethers } from "ethers";
import { deploy } from "./helpers/setup.js";
import { encodeStateBlock } from "./helpers/blocks.js";
import { executeStreams } from "./helpers/execute-blocks.js";

describe("Credit optimization", function () {
  this.timeout(120_000);
  it("preserves credit results while removing the adapter log", async () => {
    const before = await deploy("CreditBefore");
    const current = await deploy("CreditCurrent");
    const rows: Record<string, number>[] = [];
    for (const count of [0, 1, 2, 4, 8, 16, 32, 64]) {
      const [state] = executeStreams("CreditAccount", count, 2n);
      const a = await before.measure.staticCall(state, 0, 100);
      const b = await current.measure.staticCall(state, 0, 100);
      expect(Array.from(b).slice(1)).deep.eq(Array.from(a).slice(1));
      expect(b.used < a.used).eq(true);
      const oldReceipt = await (await before.measure(state, 0, 100)).wait();
      const receipt = await (await current.measure(state, 0, 100)).wait();
      // The frozen adapter logged STATE; current logging belongs to credit hooks.
      // Reported savings include this deliberate event-policy change.
      expect(oldReceipt.logs.map((log: any) => [log.topics, ethers.dataSlice(log.data, 32)]))
        .deep.eq([[[], encodeStateBlock(state)]]);
      expect(receipt.logs).deep.eq([]);
      expect(receipt.gasUsed < oldReceipt.gasUsed).eq(true);
      rows.push({ count, before: Number(a.used), after: Number(b.used), saved: Number(a.used - b.used),
        transactionSaved: Number(oldReceipt.gasUsed - receipt.gasUsed) });
    }
    console.table(rows);
  });

  it("compares copying, one topic, and an owned prefix without changing payloads", async () => {
    const logs = await deploy("CreditLogMeasure");
    const rows: Record<string, number>[] = [];
    for (const count of [0, 1, 2, 4, 8, 16, 32, 64]) {
      const [state] = executeStreams("CreditAccount", count, 2n);
      const modes = await Promise.all([0, 1, 2].map(mode => logs.measure.staticCall(state, mode)));
      for (const result of modes) expect(result.hash).eq(ethers.keccak256(state));
      // Measurements include each branch's dispatch overhead.
      rows.push({ count, copy: Number(modes[0].used), topic: Number(modes[1].used), ownedPrefix: Number(modes[2].used) });
    }
    console.table(rows);
  });
});
