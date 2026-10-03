import { expect } from "chai";
import { ethers } from "ethers";
import { writeFileSync } from "node:fs";
import { deploy } from "./helpers/setup.js";
import { encodeBlock, Keys } from "./helpers/blocks.js";

describe("Event-only output header allocation", function () {
  this.timeout(180_000);
  it("preserves returned streams, memory and headers through growth and interleaved allocations", async () => {
    const current = await deploy("OutputPrefixCurrent"), candidate = await deploy("OutputPrefixCandidate");
    const rows: any[] = [];
    const outputKey = ethers.id("#output").slice(0, 10);
    for (const payloadSize of [0, 1, 23, 24, 25, 64, 1024]) {
      const block = encodeBlock(Keys.Bytes, "0x" + "ab".repeat(payloadSize));
      for (const count of [0, 1, 4, 16]) for (const seeded of [false, true]) {
        const expected = ethers.concat(Array(count).fill(block));
        const capacity = seeded ? ethers.dataLength(expected) : 0;
        for (const interleave of [false, true]) {
          // Measure silent, current raw-log, and wrapped-log paths separately.
          for (const mode of [0, 1, 2]) {
            const args = [block, count, capacity, mode, interleave];
            const a = await current.measure.staticCall(...args), b = await candidate.measure.staticCall(...args);
            expect(a.output).eq(expected); expect(b.output).eq(expected);
            expect(b.memoryBytes - a.memoryBytes).gte(32n);
            rows.push({ payloadSize, count, seeded, interleave, mode,
              buildCurrent: Number(a.buildGas), buildCandidate: Number(b.buildGas), buildDelta: Number(b.buildGas - a.buildGas),
              memoryDelta: Number(b.memoryBytes - a.memoryBytes),
              logCurrent: Number(a.logGas), logCandidate: Number(b.logGas),
              totalDelta: Number(b.buildGas + b.logGas - a.buildGas - a.logGas) });
          }
          // Inspect actual log records across every size, capacity and growth case.
          const receipt = await (await candidate.measure(block, count, capacity, 2, interleave)).wait();
          const baselineReceipt = await (await current.measure(block, count, capacity, 2, interleave)).wait();
          expect(baselineReceipt.logs.map((l: any) => [l.topics, l.data])).deep.eq(receipt.logs.map((l: any) => [l.topics, l.data]));
          expect(receipt.logs.map((l: any) => [l.topics, l.data])).deep.eq([
            [[], ethers.concat([ethers.toBeHex(123, 32), encodeBlock(outputKey, expected)])],
          ]);
        }
      }
    }
    // Direct allocate factories must obey the same prefix contract, even at zero length.
    for (const size of [0, 1, 7, 8, 23, 24, 25, 31, 32, 33, 4096]) for (const mode of [0, 1, 2]) {
      const data = "0x" + "cd".repeat(size);
      const a = await current.allocate.staticCall(data, mode), b = await candidate.allocate.staticCall(data, mode);
      expect(a.output).eq(data); expect(b.output).eq(data);
      expect(b.memoryBytes - a.memoryBytes).eq(32n);
      const receipt = await (await candidate.allocate(data, mode)).wait();
      const expected = mode === 0 ? [] : [[[], ethers.concat([ethers.toBeHex(123, 32), mode === 2 ? encodeBlock(outputKey, data) : data])]];
      expect(receipt.logs.map((l: any) => [l.topics, l.data])).deep.eq(expected);
      rows.push({ allocateSize: size, mode, buildDelta: Number(b.buildGas - a.buildGas), memoryDelta: Number(b.memoryBytes - a.memoryBytes),
        logCurrent: Number(a.logGas), logCandidate: Number(b.logGas), totalDelta: Number(b.buildGas + b.logGas - a.buildGas - a.logGas) });
    }
    console.table(rows.filter(r => r.payloadSize === 64 && !r.interleave));
    writeFileSync("docs/benchmarks/OUTPUT_PREFIX.json", JSON.stringify({
      compiler: "solc 0.8.35, viaIR, optimizer 200, Cancun",
      scope: "Frozen old allocator versus production allocator and wrapper. Build includes init/reserve/copy/finish. Log timing excludes verification hashes and canary writes. Wrapped baseline copies output to emit the same format. ABI return encoding excluded.", rows,
    }, null, 2) + "\n");
  });
});
