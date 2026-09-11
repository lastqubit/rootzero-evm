import { expect } from "chai";
import { ethers } from "ethers";
import { mkdirSync, writeFileSync } from "node:fs";
import { deploy } from "./helpers/setup.js";
import { concat, encodeBlock, exactSpec, Keys } from "./helpers/blocks.js";

const spec = exactSpec(Keys.Bytes, 208);
const abi = ethers.AbiCoder.defaultAbiCoder();
const child = (amount: number) => encodeBlock(Keys.AccountAmount,
  abi.encode(["uint", "uint", "uint"], [1, 2, amount]));
const parent = encodeBlock(Keys.Bytes, concat(child(7), child(11)));
async function outcome(call: () => Promise<any>) {
  try { return Array.from(await call()); }
  catch (error: any) {
    const data = error.data ?? error.info?.error?.data;
    if (typeof data !== "string") throw error;
    return { error: data };
  }
}

describe("Separate more/enter versus historical enterNext", function () {
  this.timeout(120_000);
  it("benchmarks Book-style parent loops in separate contracts without a timed variant branch", async () => {
    const baseline = await deploy("TestEnterNextBaseline", spec);
    const candidate = await deploy("TestEnterNextCurrent", spec);
    const inlineVersion = await deploy("TestEnterNextInline", spec);
    const rows: any[] = [];
    for (const count of [0, 1, 8, 32, 128]) {
      const input = concat(...Array(count).fill(parent));
      const before = await baseline.measure(input);
      const after = await candidate.measure(input);
      const inline = await inlineVersion.measure(input);
      expect(inline.cursor).to.equal(before.cursor);
      expect(inline.checksum).to.equal(before.checksum);
      expect(after.cursor).to.equal(before.cursor);
      expect(after.checksum).to.equal(count % 2 ? 12n : 0n);
      expect(after.checksum).to.equal(before.checksum);
      rows.push({ count, before: Number(before.usedGas), after: Number(after.usedGas),
        saved: Number(before.usedGas - after.usedGas), inline: Number(inline.usedGas),
        inlineSaved: Number(before.usedGas - inline.usedGas), inlineExtra: Number(inline.usedGas - after.usedGas) });
    }
    console.table(rows);
    mkdirSync(".npm-cache", { recursive: true });
    writeFileSync(".npm-cache/enter-next-results.json", JSON.stringify(rows, null, 2) + "\n");
  });

  it("preserves both-lane exhaustion, exact errors, and packed metadata", async () => {
    const baseline = await deploy("TestEnterNextBaseline", spec);
    const candidate = await deploy("TestEnterNextCurrent", spec);
    const inlineVersion = await deploy("TestEnterNextInline", spec);
    for (const input of ["0x", parent, ethers.dataSlice(parent, 0, 7), ethers.dataSlice(parent, 0, 8)]) {
      for (const expected of [spec, exactSpec(Keys.String, 208), exactSpec(Keys.Bytes, 207),
        spec & ~(0xffffffffn << 160n), 0n]) {
        for (const [position, limit] of [[0, ethers.dataLength(input)], [0, 0], [0, 7], [1, 0]]) {
          for (const state of [0n, 1n << 32n, (8n << 32n) | 8n, 9n]) {
            const args = [input, expected, position, limit, state, ethers.MaxUint256 >> 128n];
            expect(await outcome(() => candidate.enterOnce(...args)))
              .to.deep.equal(await outcome(() => baseline.enterOnce(...args)));
            expect(await outcome(() => inlineVersion.enterOnce(...args)))
              .to.deep.equal(await outcome(() => candidate.enterOnce(...args)));
          }
        }
      }
    }
    // Explicit regression: exhausted input must not end iteration while state remains.
    const error = await outcome(() => candidate.enterOnce("0x", spec, 0, 0, 1n << 32n, 0));
    expect(error).to.deep.equal({ error: ethers.id("InvalidBlock()").slice(0, 10) });
    expect(await outcome(() => inlineVersion.enterOnce("0x", spec, 0, 0, 1n << 32n, 0)))
      .to.deep.equal(error);
    const ended = await candidate.enterOnce("0x", spec, 0, 0, 0, 0);
    expect(ended.entered).to.equal(false);
    // Incomplete parents and invalid children still fail during the loop body.
    for (const input of [ethers.dataSlice(parent, 0, 8), ethers.dataSlice(parent, 0, 112),
      parent + "00", encodeBlock(Keys.Bytes, "0x" + "00".repeat(208))]) {
      expect(await outcome(() => candidate.measure(input)))
        .to.deep.equal(await outcome(() => baseline.measure(input)));
      expect(await outcome(() => inlineVersion.measure(input)))
        .to.deep.equal(await outcome(() => candidate.measure(input)));
    }
  });
});
