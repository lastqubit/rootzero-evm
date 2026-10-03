import { expect } from "chai";
import { ethers } from "ethers";
import { writeFileSync } from "node:fs";
import { deploy } from "./helpers/setup.js";
import { encodeContextBlock, encodeStateBlock, encodeInputBlock } from "./helpers/blocks.js";

describe("Combined context logging", function () {
  this.timeout(120_000);
  it("preserves cursors and emits exact selected containers across unequal and empty ranges", async () => {
    const combined = await deploy("ContextLogsCombined"), separate = await deploy("ContextLogsSeparate");
    const previous = await deploy("ContextLogsPrevious");
    const rows: any[] = [];
    const account = ethers.toBeHex(7, 32), prefix = ethers.toBeHex(123, 32);
    for (const [stateSize, inputSize] of [[0, 0], [0, 7], [13, 0], [1, 31], [72, 144], [288, 288], [1152, 2304]]) {
      const state = "0x" + "ab".repeat(stateSize), input = "0x" + "cd".repeat(inputSize);
      const context = encodeContextBlock(account, state, input);
      for (let mask = 0; mask < 4; mask++) {
        const a = await separate.measure.staticCall(context, mask), b = await combined.measure.staticCall(context, mask);
        expect(Array.from(b).slice(1)).deep.eq(Array.from(a).slice(1));
        expect(b.account).eq(account); expect(b.budget).eq(19n);
        const receipt = await (await combined.measure(context, mask)).wait();
        expect(receipt.logs.map((l: any) => ({ topics: l.topics, data: l.data }))).deep.eq(mask === 0 ? [] : [{
          topics: [], data: ethers.concat([prefix, mask & 1 ? encodeStateBlock(state) : "0x", mask & 2 ? encodeInputBlock(input) : "0x"]),
        }]);
        const before = await previous.measure.staticCall(context, mask);
        expect(Array.from(before).slice(1)).deep.eq(Array.from(b).slice(1));
        const prevReceipt = await (await previous.measure(context, mask)).wait();
        expect(prevReceipt.logs.map((l: any) => [l.topics, l.data])).deep.eq(receipt.logs.map((l: any) => [l.topics, l.data]));
        rows.push({ previous: Number(before.gasUsed), saved: Number(before.gasUsed - b.gasUsed), stateSize, inputSize, mask, separate: Number(a.gasUsed), combined: Number(b.gasUsed), delta: Number(b.gasUsed - a.gasUsed) });
      }
    }
    console.table(rows.filter(r => r.stateSize === 72 || r.stateSize === 0 && r.inputSize === 0));
    writeFileSync("docs/benchmarks/CONTEXT_LOGS.json", JSON.stringify({ compiler: "solc 0.8.35, viaIR, optimizer 200, Cancun", scope: "Internal logging gas only; opening excluded. Separate logs omit headers; previous and combined retain headers. Saved compares previous checked helper with optimized production helper.", rows }, null, 2) + "\n");
  });
});
