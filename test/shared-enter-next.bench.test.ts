import { expect } from "chai";
import { mkdirSync, writeFileSync } from "node:fs";
import { ethers } from "ethers";
import { deploy } from "./helpers/setup.js";
import { concat, encodeBlock, exactSpec, Keys } from "./helpers/blocks.js";

describe("Shared validation in shorter enterNext", function () {
  it("compares the original loop, current enterNext, and shortened shared validation", async () => {
    const spec = exactSpec(Keys.Bytes, 208);
    const child = encodeBlock(Keys.AccountAmount, "0x" + "11".repeat(96));
    const parent = encodeBlock(Keys.Bytes, concat(child, child));
    const original = await deploy("TestEnterNextBaseline", spec);
    const current = await deploy("TestEnterNextCurrent", spec);
    const shared = await deploy("TestEnterNextShared", spec);
    const rows: any[] = [];
    for (const count of [0, 1, 8, 32, 128]) {
      const input = concat(...Array(count).fill(parent));
      const a = await original.measure(input);
      const b = await current.measure(input);
      const c = await shared.measure(input);
      expect(c.cursor).to.equal(a.cursor);
      expect(c.checksum).to.equal(a.checksum);
      expect(c.checksum).to.equal(b.checksum);
      rows.push({ count, original: Number(a.usedGas), current: Number(b.usedGas), shared: Number(c.usedGas),
        sharedSaved: Number(a.usedGas - c.usedGas), extraOverCurrent: Number(c.usedGas - b.usedGas) });
    }
    // The shared version must also reject exhausted input with unread state.
    let error: string | undefined;
    try { await shared.enterOnce("0x", spec, 0, 0, 1n << 32n, 0); }
    catch (e: any) { error = e.data ?? e.info?.error?.data; }
    expect(error).to.equal(ethers.id("InvalidBlock()").slice(0, 10));
    console.table(rows);
    mkdirSync(".npm-cache", { recursive: true });
    writeFileSync(".npm-cache/shared-enter-next-results.json", JSON.stringify(rows, null, 2) + "\n");
  });
});
