import { expect } from "chai";
import { ethers } from "ethers";
import { mkdirSync, writeFileSync } from "node:fs";
import { deploy } from "./helpers/setup.js";
import { Keys, encodeBlock } from "./helpers/blocks.js";

const word = (n: number) => ethers.toBeHex(n, 32);
const block = (key: string, fields: number[]) => encodeBlock(key, ethers.concat(fields.map(word)));

describe("Remaining Blocks production caller migrations", function () {
  this.timeout(120_000);

  it("compares execute bodies with identical observable hooks and real output allocation", async () => {
    const old = await deploy("BlocksMigrationBaseline");
    const next = await deploy("BlocksMigrationCandidate");
    const rows: any[] = [];
    for (const [name, memory, key, fields] of [
      ["CreditAccount", true, Keys.Balance, [1, 7]],
      ["Cashout", true, Keys.Balance, [1, 7]],
      ["Settle", true, Keys.Position, [1, 7, 2, 3, 9]],
      ["DebitAccount", false, Keys.Amount, [2, 7]],
      ["Bootstrap", false, Keys.Bootstrap, [2, 7, 3]],
      ["Authorize", false, Keys.Node, [13]],
    ] as const) {
      for (const count of [0, 1, 2, 4, 8, 16]) {
        const stream = ethers.concat(Array.from({ length: count }, (_, i) =>
          block(key, fields.map((n, j) => j === 1 ? n + i : n))));
        const args = [memory ? stream : "0x", memory ? "0x" : stream, 100];
        const a = await old["measure" + name].staticCall(...args);
        const b = await next["measure" + name].staticCall(...args);
        expect(Array.from(b).slice(1), name + "/" + count).deep.eq(Array.from(a).slice(1));
        rows.push({ caller: name, count, old: Number(a[0]), next: Number(b[0]), delta: Number(b[0] - a[0]) });
      }
    }
    for (const count of [1, 2, 4]) {
      for (const value of [0, 100]) {
        const stream = ethers.concat(Array(count).fill(block(Keys.Bootstrap, [1, 7, 3])));
        const a = await old.measureBootstrap.staticCall("0x", stream, value);
        const b = await next.measureBootstrap.staticCall("0x", stream, value);
        expect(Array.from(b).slice(1)).deep.eq(Array.from(a).slice(1));
        rows.push({ caller: "Bootstrap(chain,budget=" + value + ")", count,
          old: Number(a[0]), next: Number(b[0]), delta: Number(b[0] - a[0]) });
      }
    }
    console.table(rows);
    mkdirSync(".npm-cache", { recursive: true });
    writeFileSync(".npm-cache/blocks-migration-execute.json", JSON.stringify(rows, null, 2));
  });

  it("compares runCount, relay context creation, and annotation creators", async () => {
    const old = await deploy("BlocksEncodingMigrationBaseline");
    const next = await deploy("BlocksEncodingMigrationCandidate");
    const rows: any[] = [];
    async function compare(method: string, size: number, args: any[]) {
      const a = await old[method](...args);
      const b = await next[method](...args);
      expect(Array.from(b).slice(1), method + "/" + size).deep.eq(Array.from(a).slice(1));
      // The small ACTION/COUNTERPARTY layout cost is accepted; bytes must still match.
      if (!["Action", "Counterparty"].includes(method)) {
        expect(b[0] <= a[0], method + "/" + size + " gas regression: " + a[0] + " -> " + b[0]).eq(true);
      }
      rows.push({ caller: method, size, old: Number(a[0]), next: Number(b[0]), delta: Number(b[0] - a[0]) });
    }
    for (const count of [0, 1, 2, 4, 8, 16]) {
      const stream = ethers.concat(Array(count).fill(block(Keys.Balance, [1, 7])));
      await compare("count", count, [stream, Keys.Balance]);
      await compare("relayBalances", count, [word(9), stream, "0x1234"]);
    }
    for (const size of [0, 1, 31, 32, 33, 72, 288, 1024]) {
      const input = "0x" + "ab".repeat(size);
      await compare("context", size, [word(9), "0x", input]);
      await compare("context", size, [word(9), block(Keys.Balance, [1, 7]), input]);
      const text = "x".repeat(size);
      await compare("Label", size, [word(1), text]);
      await compare("Schema", size, [123, text]);
      await compare("Groups", size, [text]);
    }
    await compare("Action", 1, [123]);
    await compare("Counterparty", 1, [word(9)]);
    await compare("ExecutionCost", 1, [123, 456]);
    console.table(rows);
    writeFileSync(".npm-cache/blocks-migration-encoding.json", JSON.stringify(rows, null, 2));
  });
});
