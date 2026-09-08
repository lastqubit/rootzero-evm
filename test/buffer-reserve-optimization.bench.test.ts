import { expect } from "chai";
import { ethers } from "ethers";
import { mkdirSync, writeFileSync } from "node:fs";
import { deploy } from "./helpers/setup.js";

async function outcome(call: () => Promise<any>) {
  try { const r = await call(); return { cursor: r.cursor, position: r.position, footprint: r.footprint, output: r.output }; }
  catch (error: any) {
    const data = error.data ?? error.info?.error?.data;
    if (typeof data !== "string") throw error;
    return { error: data };
  }
}
describe("Buffer reserve arithmetic optimization", function () {
  this.timeout(120_000);
  it("preserves allocation size, copied prefix, and zero initialization while reducing gas", async () => {
    const helper = await deploy("TestBufferReserveOptimization");
    const rows: any[] = [];
    for (const capacity of [0, 32, 64, 256, 4096]) {
      for (const backing of [0, capacity ? capacity + 32 : 32]) {
        for (const advance of [0, 8, 32, 72, 256, 4096]) {
          const position = backing ? Math.min(capacity, 16) : 0;
          const cfg = { cursor: (BigInt(capacity) << 32n) | BigInt(position), backing, advance, touch: advance + 24 };
          const before = await helper.measure(false, cfg);
          const after = await helper.measure(true, cfg);
          expect(after.cursor).to.equal(before.cursor);
          expect(after.position).to.equal(before.position);
          expect(after.footprint).to.equal(before.footprint);
          expect(after.output).to.equal(before.output);
          expect(after.usedGas).to.be.lessThan(before.usedGas);
          rows.push({ capacity, backing, advance, before: Number(before.usedGas), after: Number(after.usedGas),
            saved: Number(before.usedGas - after.usedGas) });
        }
      }
    }
    mkdirSync(".npm-cache", { recursive: true });
    writeFileSync(".npm-cache/buffer-reserve-results.json", JSON.stringify(rows, null, 2) + "\n");
    console.table(rows.filter(row => [0, 256].includes(row.capacity) && row.advance === 72));
  });

  it("preserves exact errors and reserved high bits on adversarial cursors and sizes", async () => {
    const helper = await deploy("TestBufferReserveOptimization");
    const cursors = [0n, 1n, (64n << 32n) | 8n, 0xffffffffn, 0xffffffff00000000n,
      ethers.MaxUint256, (ethers.MaxUint256 >> 64n << 64n) | (64n << 32n) | 8n];
    for (const cursor of cursors) {
      for (const advance of [0n, 8n, 65n, 1n << 32n, ethers.MaxUint256]) {
        for (const touch of [0n, advance, ethers.MaxUint256]) {
          // Avoid a successful allocation of four GiB from an enormous capacity hint.
          const capacity = (cursor >> 32n) & 0xffffffffn;
          const backing = capacity > 10000n ? 64 : 0;
          const cfg = { cursor, backing, advance, touch };
          const before = await outcome(() => helper.measure(false, cfg));
          expect(await outcome(() => helper.measure(true, cfg))).to.deep.equal(before);
        }
      }
    }
  });
});
