import { expect } from "chai";
import { ethers } from "ethers";
import { mkdirSync, writeFileSync } from "node:fs";
import { deploy } from "./helpers/setup.js";
import { concat, encodeBlock, encodeBytesBlock, encodeContextBlock, encodeBalanceBlock, Keys } from "./helpers/blocks.js";

describe("Blocks optimization benchmark", function () {
  this.timeout(120_000);

  it("preserves factory bytes, padding, scratch space, and allocation in dirty memory", async () => {
    const helper = await deploy("TestBlocksOptimization");
    const rows: object[] = [];
    for (const kind of [0, 1, 2, 3, 4]) {
      for (const size of kind >= 3 ? [0] : [0, 1, 7, 8, 9, 23, 24, 25, 31, 32, 33, 63, 64, 65, 256, 4096, 65536]) {
        const a = "0x" + "ab".repeat(size);
        const b = "0x" + "cd".repeat(size % 35);
        const expected = kind == 2 ? encodeContextBlock(ethers.toBeHex(1, 32), a, b)
          : kind == 3 ? encodeBytesBlock("0x")
          : kind == 4 ? encodeBalanceBlock(ethers.toBeHex(1, 32), 2n) : encodeBytesBlock(a);
        const before = await helper.factory(false, kind, a, b);
        const after = await helper.factory(true, kind, a, b);
        for (const result of [before, after]) {
          expect(result.output).to.equal(expected);
          expect(result.cleanTail, `clean tail kind=${kind} size=${size} optimized=${result === after}`).to.equal(true);
          expect(result.guardIntact, `guard kind=${kind} size=${size} optimized=${result === after}`).to.equal(true);
        }
        expect(after.retained).to.equal(before.retained);
        rows.push({ kind, size, before: Number(before.usedGas), after: Number(after.usedGas),
          saved: Number(before.usedGas - after.usedGas) });
        if (size >= 4096) expect(after.usedGas).to.be.lessThan(before.usedGas);
      }
    }
    mkdirSync(".npm-cache", { recursive: true });
    writeFileSync(".npm-cache/blocks-factory-results.json", JSON.stringify(rows, null, 2) + "\n");
    console.table(rows.filter((r: any) => [0, 256, 4096, 65536].includes(r.size)));
  });

  it("preserves scan results and malformed-block errors", async () => {
    const helper = await deploy("TestBlocksOptimization");
    const matching = encodeBytesBlock("0xaabb");
    const different = encodeBlock(Keys.Balance, "0x");
    const malformed = Keys.Balance + "ffffffff";
    const sources = ["0x", matching, different, concat(matching, different),
      concat(different, matching), malformed, concat(matching, malformed)];
    // Every truncated header and payload, including a nonmatching key.
    for (let i = 1; i < ethers.dataLength(matching); i++) {
      sources.push(ethers.dataSlice(matching, 0, i));
    }
    async function outcome(optimized: boolean, find: boolean, source: string, start: number, length: number) {
      try {
        const result = await helper.scan(optimized, find, source, start, length, Keys.Bytes);
        return { total: result.total, end: result.end };
      } catch (error: any) {
        const data = error.data ?? error.info?.error?.data;
        expect(data).to.be.a("string");
        return { error: data };
      }
    }
    for (const source of sources) {
      const size = ethers.dataLength(source);
      for (const find of [false, true]) {
        for (const start of [0, size, size + 1]) {
          for (const length of new Set([size, Math.max(0, size - 1)])) {
            expect(await outcome(true, find, source, start, length))
              .to.deep.equal(await outcome(false, find, source, start, length));
          }
        }
      }
    }
    // Validation must happen before a mismatching key terminates the scan.
    for (const find of [false, true]) {
      expect(await outcome(true, find, malformed, 0, 8))
        .to.deep.equal({ error: ethers.id("MalformedBlocks()").slice(0, 10) });
    }
  });

  it("reduces gas per scanned block", async () => {
    const helper = await deploy("TestBlocksOptimization");
    const rows: object[] = [];
    for (const count of [0, 1, 8, 64, 256]) {
      const input = concat(...Array.from({ length: count }, () => encodeBytesBlock("0x1234")));
      for (const find of [false, true]) {
        const key = find ? Keys.Balance : Keys.Bytes;
        const before = await helper.scan(false, find, input, 0, ethers.dataLength(input), key);
        const after = await helper.scan(true, find, input, 0, ethers.dataLength(input), key);
        expect([after.total, after.end]).to.deep.equal([before.total, before.end]);
        if (count > 0) expect(after.usedGas).to.be.lessThan(before.usedGas);
        rows.push({ count, operation: find ? "find" : "run", before: Number(before.usedGas),
          after: Number(after.usedGas), saved: Number(before.usedGas - after.usedGas) });
      }
    }
    mkdirSync(".npm-cache", { recursive: true });
    writeFileSync(".npm-cache/blocks-scan-results.json", JSON.stringify(rows, null, 2) + "\n");
    console.table(rows);
  });
});
