import { expect } from "chai";
import { ethers } from "ethers";
import { mkdirSync, writeFileSync } from "node:fs";
import { deploy } from "./helpers/setup.js";

async function outcome(call: () => Promise<any>, navigation = false) {
  try {
    const r = await call();
    return navigation ? { updated: r.updated, position: r.position }
      : { cursor: r.cursor, footprint: r.footprint, output: r.output };
  } catch (error: any) {
    const data = error.data ?? error.info?.error?.data;
    if (typeof data !== "string") throw error;
    return { error: data };
  }
}

describe("Raw writer and cursor optimization", function () {
  this.timeout(120_000);

  it("preserves cursor metadata and navigation results while saving gas", async () => {
    const helper = await deploy("TestRawWriterCursorOptimization");
    const rows: any[] = [];
    for (const consume of [false, true]) {
      for (const count of [1, 8, 32]) {
        for (const flags of [0n, 255n, ethers.MaxUint256 >> 64n]) {
          const cur = (flags << 64n) | (0xffffffffn << 32n) | 17n;
          const before = await helper.navigate(false, consume, cur, 31, count);
          const after = await helper.navigate(true, consume, cur, 31, count);
          expect(after.updated).to.equal(cur + 31n * BigInt(count));
          expect(after.updated).to.equal(before.updated);
          expect(after.position).to.equal(consume ? 17n + 31n * BigInt(count - 1) : 0n);
          expect(after.position).to.equal(before.position);
          expect(after.usedGas).to.be.lessThan(before.usedGas);
          if (flags === 0n) rows.push({ consume, count, saved: Number(before.usedGas - after.usedGas) });
        }
      }
    }
    console.table(rows);
  });

  it("preserves exact errors and endpoint behavior for arbitrary packed cursors", async () => {
    const helper = await deploy("TestRawWriterCursorOptimization");
    for (const consume of [false, true]) {
      for (const cur of [0n, 1n, 0xffffffffn, 0xffffffff00000000n, ethers.MaxUint256,
        (64n << 32n) | 8n, (ethers.MaxUint256 >> 64n << 64n) | (64n << 32n) | 8n]) {
        for (const amount of [0n, 1n, 56n, 57n, 0xffffffffn, 1n << 32n, ethers.MaxUint256]) {
          const before = await outcome(() => helper.navigate(false, consume, cur, amount, 1), true);
          expect(await outcome(() => helper.navigate(true, consume, cur, amount, 1), true)).to.deep.equal(before);
        }
      }
    }
  });

  it("preserves every physical byte and allocation across raw writes and growth", async () => {
    const helper = await deploy("TestRawWriterCursorOptimization");
    const rows: any[] = [];
    for (let mode = 0; mode < 5; mode++) {
      for (const capacity of [0, 64, 4096]) {
        for (const count of [1, 8]) {
          for (const size of [0, 1, 31, 32, 33, 256]) {
            const input = ethers.hexlify(Uint8Array.from({ length: size }, (_, j) => (j * 7 + 3) % 256));
            const cfg = { mode, capacity, keep: size, count, aliasInput: false };
            const before = await helper.measure(false, cfg, input);
            const after = await helper.measure(true, cfg, input);
            expect(after.cursor).to.equal(before.cursor);
            expect(after.footprint).to.equal(before.footprint);
            expect(after.output).to.equal(before.output);
            expect(after.usedGas).to.be.lessThan(before.usedGas);
            const physical = new Uint8Array(ethers.getBytes(after.output).length);
            physical.set(ethers.getBytes("0x12345678"));
            let position = 4;
            const words = [0x1111, 0x2222, 0x3333].slice(0, mode - 1)
              .map(word => ethers.zeroPadValue(ethers.toBeHex(word), 32));
            const write = mode < 2 ? ethers.getBytes(input) : ethers.getBytes(ethers.concat(words));
            const advance = mode < 2 ? size : 32 * (mode - 2) + size;
            for (let j = 0; j < count; j++) {
              // resize copies only the written prefix, dropping scratch tail bytes.
              // For these monotonic equal-sized writes the final tail is rewritten.
              physical.set(write, position);
              position += advance;
            }
            expect(after.cursor & 0xffffffffn).to.equal(BigInt(position));
            expect(after.output).to.equal(ethers.hexlify(physical));
            rows.push({ mode, capacity, count, size, saved: Number(before.usedGas - after.usedGas) });
          }
        }
      }
    }
    mkdirSync(".npm-cache", { recursive: true });
    writeFileSync(".npm-cache/raw-writer-results.json", JSON.stringify(rows, null, 2) + "\n");
    console.table(rows.filter(r => r.capacity === 0 && r.size === 31));
  });

  it("preserves aliased memory copies and errors from overflowing keep values", async () => {
    const helper = await deploy("TestRawWriterCursorOptimization");
    for (const capacity of [0, 64, 256]) {
      const cfg = { mode: 0, capacity, keep: 0, count: 3, aliasInput: true };
      expect(await outcome(() => helper.measure(true, cfg, "0x")))
        .to.deep.equal(await outcome(() => helper.measure(false, cfg, "0x")));
    }
    for (const mode of [2, 3, 4]) {
      for (const keep of [1n << 32n, ethers.MaxUint256 - 63n, ethers.MaxUint256 - 31n, ethers.MaxUint256]) {
        const cfg = { mode, capacity: 0, keep, count: 1, aliasInput: false };
        expect(await outcome(() => helper.measure(true, cfg, "0x")))
          .to.deep.equal(await outcome(() => helper.measure(false, cfg, "0x")));
      }
    }
  });
});
