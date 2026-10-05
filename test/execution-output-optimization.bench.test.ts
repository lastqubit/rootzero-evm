import { expect } from "chai";
import { ethers } from "ethers";
import { mkdirSync, writeFileSync } from "node:fs";
import { deploy } from "./helpers/setup.js";
import { encodeBlock, encodeStepBlock, encodeCallBlock, encodeDispatchBlock, encodeRelayBlock,
  encodeContextBlock, encodeRecoverBlock, Keys } from "./helpers/blocks.js";

const word = ethers.toBeHex(33, 32);
const blob = (size: number) => "0x" + "ab".repeat(size);
const prefix = encodeBlock(ethers.id("#bytes").slice(0, 10), "0x");
const layouts: Record<string, (a: string, b: string) => string> = {
  Step: (a, b) => encodeStepBlock(11n, 22n, a),
  Call: (a, b) => encodeCallBlock(11n, 22n, a),
  Dispatch: (a, b) => encodeDispatchBlock(11n, 22n, a),
  Relay: encodeRelayBlock,
  Context: (a, b) => encodeContextBlock(word, a, b),
  Recover: (a, b) => encodeRecoverBlock(11n, 22n, word, a),
  Label: (a, b) => encodeBlock(Keys.Label, ethers.concat([word, encodeBlock(Keys.String, a)])),
  Schema: (a, b) => encodeBlock(Keys.Schema, ethers.concat([ethers.toBeHex(11, 32), encodeBlock(Keys.String, a)])),
  Block: (a, b) => encodeBlock(Keys.Bytes, a),
  List: (a, b) => encodeBlock(Keys.List, a),
  Bytes: (a, b) => encodeBlock(Keys.Bytes, a),
  String: (a, b) => encodeBlock(Keys.String, a),
};
const methods = [
  ...["Step", "Call", "Dispatch", "Relay", "Context", "Recover", "Label", "Schema"].map(name => ({ name, method: "output" + name })),
  ...["Block", "List", "Bytes", "String", "Step", "Call", "Dispatch", "Relay", "Context", "Recover"].map(name => ({ name, method: "output" + name + "Wrap" })),
];
async function failure(call: () => Promise<any>) {
  try { await call(); return undefined; }
  catch (error: any) {
    const data = error.data ?? error.info?.error?.data;
    if (typeof data !== "string") throw error;
    return data;
  }
}
describe("Execution cursor encoder migration", function () {
  this.timeout(180_000);
  it("compares every output layout across buffer growth and preallocated capacity", async () => {
    const helper = await deploy("TestExecutionOutputOptimization");
    const rows: any[] = [];
    for (const { name, method } of methods) {
      for (const size of [0, 1, 31, 32, 33, 256, 4096]) {
        const a = blob(size), b = blob(size % 35);
        const blockSize = ethers.dataLength(layouts[name](a, b));
        const prefixSize = ethers.dataLength(prefix);
        for (const [count, capacity] of [[1, 0], [4, 0], [1, prefixSize + blockSize], [2, prefixSize + 2 * blockSize], [4, prefixSize + 4 * blockSize]]) {
          const opts = { count, capacity, forgedLength: 0 };
          const before = await helper[method](false, a, b, opts);
          const after = await helper[method](true, a, b, opts);
          const expected = ethers.concat([prefix, ...Array(count).fill(layouts[name](a, b))]);
          expect(before.output).to.equal(expected);
          expect(after.output).to.equal(expected);
          // Each grown buffer now owns a reserved word before its length.
          let allocated = capacity || 64, written = prefixSize, growths = 0;
          for (let i = 0; i < count; i++) {
            if (written + blockSize > allocated) {
              do { allocated *= 2; } while (written + blockSize > allocated);
              growths++;
            }
            written += blockSize;
          }
          expect(after.footprint).to.equal(before.footprint + 32n * BigInt(growths));
          // Record tradeoffs: primitive composition and cursor conversion need
          // not beat the frozen assembly writer at every compiler call site.
          rows.push({ operation: method, size, count, capacity,
            beforeBytes: Number(before.footprint), afterBytes: Number(after.footprint),
            before: Number(before.usedGas), after: Number(after.usedGas), saved: Number(before.usedGas - after.usedGas) });
        }
      }
    }
    mkdirSync(".npm-cache", { recursive: true });
    writeFileSync(".npm-cache/execution-output-results.json", JSON.stringify(rows, null, 2) + "\n");
    console.table(rows.filter(row => row.size === 0 && row.count === 1));
  });

  it("rejects oversized memory payloads and unrepresentable calldata source cursors", async () => {
    const helper = await deploy("TestExecutionOutputOptimization");
    for (const { method } of methods) {
      for (const forgedLength of [(1n << 32n) - 1n, 1n << 32n, ethers.MaxUint256]) {
        const opts = { count: 1, capacity: 0, forgedLength };
        const before = await failure(() => helper[method](false, "0x", "0x", opts));
        expect(before).to.be.a("string");
        expect(await failure(() => helper[method](true, "0x", "0x", opts))).to.equal(before);
      }
    }
  });

  it("handles empty first or second payloads at nonzero output positions", async () => {
    const helper = await deploy("TestExecutionOutputOptimization");
    for (const name of ["Relay", "Context"]) {
      for (const method of ["output" + name, "output" + name + "Wrap"]) {
        for (const [a, b] of [["0x", blob(33)], [blob(33), "0x"], [blob(1), blob(4096)]]) {
          const opts = { count: 4, capacity: 0, forgedLength: 0 };
          const expected = ethers.concat([prefix, ...Array(4).fill(layouts[name](a, b))]);
          for (const optimized of [false, true]) expect((await helper[method](optimized, a, b, opts)).output).to.equal(expected);
        }
      }
    }
  });
});
