import { expect } from "chai";
import { ethers } from "ethers";
import { mkdirSync, writeFileSync } from "node:fs";
import { deploy } from "./helpers/setup.js";
import { encodeBlock, Keys } from "./helpers/blocks.js";

describe("Bounded block inspection optimization", function () {
  this.timeout(120_000);

  async function outcome(call: () => Promise<any>, measured = true) {
    try {
      const result = await call();
      return { result: [...result].slice(measured ? 1 : 0) };
    } catch (error: any) {
      const data = error.data ?? error.info?.error?.data;
      expect(data).to.be.a("string");
      return { error: data };
    }
  }

  it("preserves outputs and revert data across logical boundaries and malformed headers", async () => {
    const helper = await deploy("TestBlockInspection");
    const sources = [encodeBlock(Keys.Bytes, "0x"), encodeBlock(Keys.Bytes, "0xaabb"),
      encodeBlock(Keys.Balance, "0x"), encodeBlock("0x00000000", "0x"),
      encodeBlock("0xffffffff", "0x"), Keys.Bytes + "ffffffff"];
    for (let n = 0; n < 8; ++n) sources.push(ethers.dataSlice(encodeBlock(Keys.Bytes, "0x"), 0, n));
    for (const source of sources) {
      const length = ethers.dataLength(source);
      for (const mode of [0, 1, 2]) {
        for (const key of [Keys.Bytes, "0x00000000", "0xffffffff"]) {
          for (const [start, end] of [[0, length], [0, Math.max(0, length - 1)], [length, length], [length + 1, length]]) {
            expect(await outcome(() => helper.inspect(true, mode, source, start, end, key, 1)))
              .to.deep.equal(await outcome(() => helper.inspect(false, mode, source, start, end, key, 1)));
          }
        }
      }
    }
    // hasAt only requires a header, whereas peek validates the declared payload too.
    const malformed = Keys.Bytes + "ffffffff";
    expect((await helper.inspect(true, 1, malformed, 0, 8, Keys.Bytes, 1)).matches).to.equal(true);
    expect(await outcome(() => helper.inspect(true, 0, malformed, 0, 8, Keys.Bytes, 1)))
      .to.deep.equal({ error: ethers.id("MalformedBlocks()").slice(0, 10) });
    expect((await helper.inspect(true, 2, malformed, 0, 8, Keys.Bytes, 1)).matches).to.equal(false);
  });

  it("preserves behavior for extreme absolute positions", async () => {
    const helper = await deploy("TestBlockInspection");
    const max = ethers.MaxUint256;
    for (const [start, end] of [[max, 0n], [max, max], [max - 7n, max],
      [max - 8n, max], [max - 9n, max], [1n << 255n, (1n << 255n) + 8n]]) {
      for (const mode of [0, 1, 2]) {
        for (const key of ["0x00000000", "0xffffffff"]) {
          expect(await outcome(() => helper.raw(true, mode, start, end, key), false))
            .to.deep.equal(await outcome(() => helper.raw(false, mode, start, end, key), false));
        }
      }
    }
  });

  it("benchmarks complete headers and key matches/mismatches", async () => {
    const helper = await deploy("TestBlockInspection");
    const rows: object[] = [];
    for (const mode of [0, 1, 2]) {
      for (const bytes of [0, 33]) {
        const source = encodeBlock(Keys.Bytes, "0x" + "ab".repeat(bytes));
        for (const match of [true, false]) {
          const key = match ? Keys.Bytes : Keys.Balance;
          const before = await helper.inspect(false, mode, source, 0, ethers.dataLength(source), key, 64);
          const after = await helper.inspect(true, mode, source, 0, ethers.dataLength(source), key, 64);
          expect([...after].slice(1)).to.deep.equal([...before].slice(1));
          expect(after.usedGas).to.be.lessThan(before.usedGas);
          rows.push({ operation: ["peek", "hasAt", "isEmpty"][mode], bytes, match,
            before: Number(before.usedGas), after: Number(after.usedGas),
            savedPerInspection: Number(before.usedGas - after.usedGas) / 64 });
        }
      }
    }
    mkdirSync(".npm-cache", { recursive: true });
    writeFileSync(".npm-cache/block-inspection-results.json", JSON.stringify(rows, null, 2) + "\n");
    console.table(rows);
  });
});
