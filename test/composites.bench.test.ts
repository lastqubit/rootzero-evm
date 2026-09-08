import { expect } from "chai";
import { ethers } from "ethers";
import { mkdirSync, writeFileSync } from "node:fs";
import { deploy } from "./helpers/setup.js";
import { encodeStepBlock, encodeCallBlock, encodeDispatchBlock, encodeRelayBlock,
  encodeContextBlock, encodeRecoverBlock, encodeAnnotationBlock } from "./helpers/blocks.js";

const word = ethers.toBeHex(33, 32);
const layouts = [
  { name: "Step", fixed: 64, encode: (a: string, b: string) => encodeStepBlock(11n, 22n, a) },
  { name: "Call", fixed: 64, encode: (a: string, b: string) => encodeCallBlock(11n, 22n, a) },
  { name: "Dispatch", fixed: 64, encode: (a: string, b: string) => encodeDispatchBlock(11n, 22n, a) },
  { name: "Relay", fixed: 0, encode: encodeRelayBlock },
  { name: "Context", fixed: 32, encode: (a: string, b: string) => encodeContextBlock(word, a, b) },
  { name: "Recover", fixed: 96, encode: (a: string, b: string) => encodeRecoverBlock(11n, 22n, word, a) },
  { name: "Annotation", fixed: 32, encode: (a: string, b: string) => encodeAnnotationBlock(11n, a) },
];
const blob = (size: number) => "0x" + "ab".repeat(size);
const replace = (data: string, offset: number, value: string) => ethers.concat([
  ethers.dataSlice(data, 0, offset), value, ethers.dataSlice(data, offset + ethers.dataLength(value)),
]);
async function outcome(call: () => Promise<any>) {
  try { return { output: (await call()).output }; }
  catch (error: any) {
    const data = error.data ?? error.info?.error?.data;
    if (typeof data !== "string") throw error;
    return { error: data };
  }
}

describe("Composite factory and decoder optimization", function () {
  this.timeout(180_000);
  it("benchmarks all layouts and both input locations against frozen implementations", async () => {
    const helper = await deploy("TestComposites");
    const rows: any[] = [];
    for (const layout of layouts) {
      for (const size of [0, 1, 31, 32, 33, 256, 4096]) {
        const a = blob(size), b = blob(size % 35);
        const encoded = layout.encode(a, b);
        if (layout.name !== "Annotation") {
          for (const suffix of ["", "Copy"]) {
            const method = helper["factory" + layout.name + suffix];
            const before = await method(false, a, b, 0);
            const after = await method(true, a, b, 0);
            expect(before.output).to.equal(encoded);
            expect(after.output).to.equal(encoded);
            expect(before.cleanTail && after.cleanTail).to.equal(true);
            expect(after.usedGas).to.be.lessThan(before.usedGas);
            rows.push({ operation: "create" + layout.name + suffix, size,
              before: Number(before.usedGas), after: Number(after.usedGas),
              saved: Number(before.usedGas - after.usedGas) });
          }
        }
        const method = helper["decode" + layout.name];
        const prefixed = ethers.concat(["0xaabbcc", encoded, "0xdeadbeef"]);
        const before = await method(false, prefixed, 3, false);
        const after = await method(true, prefixed, 3, false);
        expect(after.output).to.equal(before.output);
        expect(after.usedGas).to.be.lessThan(before.usedGas);
        rows.push({ operation: "unpack" + layout.name, size,
          before: Number(before.usedGas), after: Number(after.usedGas),
          saved: Number(before.usedGas - after.usedGas) });
      }
    }
    mkdirSync(".npm-cache", { recursive: true });
    writeFileSync(".npm-cache/composite-results.json", JSON.stringify(rows, null, 2) + "\n");
    console.table(rows.filter(row => row.size === 0));
  });

  it("preserves child validation, truncation behavior, and absolute boundary errors", async () => {
    const helper = await deploy("TestComposites");
    for (const layout of layouts) {
      const encoded = layout.encode(blob(3), blob(5));
      const first = 8 + layout.fixed;
      const children = [first];
      if (["Relay", "Context"].includes(layout.name)) children.push(first + 8 + 3);
      const samples = [encoded, "0x", replace(encoded, 0, "0xffffffff")];
      for (const length of [0, 1, ethers.dataLength(encoded) - 9, ethers.dataLength(encoded) - 7, 0xffffffff]) {
        samples.push(replace(encoded, 4, ethers.toBeHex(length, 4)));
      }
      for (const child of children) {
        samples.push(replace(encoded, child, "0xffffffff"));
        for (const length of [0, 1, 4, 0xffffffff]) {
          samples.push(replace(encoded, child + 4, ethers.toBeHex(length, 4)));
        }
      }
      for (const length of [1, 7, 8, first, first + 7, ethers.dataLength(encoded) - 1]) {
        samples.push(ethers.dataSlice(encoded, 0, length));
      }
      const method = helper["decode" + layout.name];
      for (const data of samples) {
        const before = await outcome(() => method(false, data, 0, false));
        expect(await outcome(() => method(true, data, 0, false))).to.deep.equal(before);
      }
      for (const abs of [ethers.MaxUint256, ethers.MaxUint256 - 7n, ethers.MaxUint256 - 103n, 1n << 32n]) {
        const before = await outcome(() => method(false, encoded, abs, true));
        expect(before).to.deep.equal({ error: ethers.id("InvalidBlock()").slice(0, 10) });
        expect(await outcome(() => method(true, encoded, abs, true))).to.deep.equal(before);
      }
    }
  });

  it("retains factory size rejection and arithmetic-overflow errors before copying", async () => {
    const helper = await deploy("TestComposites");
    for (const layout of layouts.slice(0, 6)) {
      for (const suffix of ["", "Copy"]) {
        const method = helper["factory" + layout.name + suffix];
        const overhead = ethers.dataLength(layout.encode("0x", "0x"));
        for (const length of [(1n << 32n) - BigInt(overhead), 1n << 32n, ethers.MaxUint256]) {
          const before = await outcome(() => method(false, "0x", "0x", length));
          expect(before.error).to.equal(length === ethers.MaxUint256
            ? ethers.concat(["0x4e487b71", ethers.toBeHex(0x11, 32)])
            : ethers.id("ValueOverflow()").slice(0, 10));
          expect(await outcome(() => method(true, "0x", "0x", length))).to.deep.equal(before);
        }
      }
    }
  });
});
