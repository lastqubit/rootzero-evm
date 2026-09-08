import { expect } from "chai";
import { ethers } from "ethers";
import { mkdirSync, writeFileSync } from "node:fs";
import { deploy } from "./helpers/setup.js";
import { encodeBlock, exactSpec, rangedSpec, Keys } from "./helpers/blocks.js";

const blob = (size: number) => "0x" + "ab".repeat(size);
async function outcome(call: () => Promise<any>) {
  try { return { output: (await call()).output }; }
  catch (error: any) {
    const data = error.data ?? error.info?.error?.data;
    if (typeof data !== "string") throw error;
    return { error: data };
  }
}
const leaves = [["unpackList", Keys.List], ["unpackBytes", Keys.Bytes], ["unpackString", Keys.String]];
describe("Leaf decoding and fixed header optimization", function () {
  this.timeout(120_000);
  it("compares execution gas and decoded output with frozen implementations", async () => {
    const helper = await deploy("TestLeafFixed");
    const rows: any[] = [];
    async function compare(operation: string, input: string, size: number, extra: any[] = []) {
      const data = ethers.concat(["0xaabbcc", input, "0xdeadbeef"]);
      const before = await helper[operation](false, data, 3, false, ...extra);
      const after = await helper[operation](true, data, 3, false, ...extra);
      expect(after.output).to.equal(before.output);
      expect(after.usedGas).to.be.lessThan(before.usedGas);
      rows.push({ operation, size, before: Number(before.usedGas), after: Number(after.usedGas),
        saved: Number(before.usedGas - after.usedGas) });
    }
    for (const [operation, key] of leaves) {
      for (const size of [0, 1, 31, 32, 33, 256, 4096]) {
        await compare(operation, encodeBlock(key, blob(size)), size);
      }
    }
    for (const size of [32, 64, 96, 128, 160]) {
      await compare("unpack" + size, encodeBlock(Keys.List, blob(size)), size, [exactSpec(Keys.List, size)]);
    }
    await compare("expectEmpty", encodeBlock(Keys.List, "0x"), 0, [Keys.List]);
    mkdirSync(".npm-cache", { recursive: true });
    writeFileSync(".npm-cache/leaf-fixed-results.json", JSON.stringify(rows, null, 2) + "\n");
    console.table(rows.filter(row => row.size === 0 || /^unpack\d/.test(row.operation)));
  });

  it("preserves leaf key errors, zero padding, truncation, and extreme positions", async () => {
    const helper = await deploy("TestLeafFixed");
    for (const [operation, key] of leaves) {
      const method = helper[operation];
      const valid = encodeBlock(key, blob(33));
      const inputs = [valid, "0x", encodeBlock("0x00000000", "0x"), encodeBlock("0xffffffff", blob(3))];
      for (let length = 0; length < ethers.dataLength(valid); length++) inputs.push(ethers.dataSlice(valid, 0, length));
      // Keep declared lengths modest: the fixture ABI-copies returned slices.
      for (const length of [0, 1, 31, 32, 34, 255]) inputs.push(ethers.concat([key, ethers.toBeHex(length, 4), blob(33)]));
      for (const input of inputs) {
        expect(await outcome(() => method(true, input, 0, false)))
          .to.deep.equal(await outcome(() => method(false, input, 0, false)));
      }
      for (const abs of [ethers.MaxUint256, ethers.MaxUint256 - 7n, ethers.MaxUint256 - 40n, 1n << 32n]) {
        const before = await outcome(() => method(false, valid, abs, true));
        expect(before.error).to.equal(ethers.id("InvalidBlock()").slice(0, 10));
        expect(await outcome(() => method(true, valid, abs, true))).to.deep.equal(before);
      }
    }
  });

  it("preserves fixed sizes, arbitrary keys, spec handling, and empty-header overflow", async () => {
    const helper = await deploy("TestLeafFixed");
    for (const key of [Keys.List, "0x00000000", "0xffffffff"]) {
      for (const size of [0, 32, 64, 96, 128, 160]) {
        const method = helper[size ? "unpack" + size : "expectEmpty"];
        // Fixed unpackers use only the spec key and enforce their own fixed size.
        const extra = size ? rangedSpec(key, 1, 2, 0) : key;
        const valid = encodeBlock(key, blob(size));
        const inputs = [valid, "0x", encodeBlock(key, blob(size + 1)),
          encodeBlock(Keys.String, blob(size)), ethers.concat([key, "0xffffffff"]),
          ethers.dataSlice(valid, 0, 7), ethers.dataSlice(valid, 0, 8),
          ethers.dataSlice(valid, 0, Math.max(0, ethers.dataLength(valid) - 1))];
        for (const input of inputs) {
          expect(await outcome(() => method(true, input, 0, false, extra)))
            .to.deep.equal(await outcome(() => method(false, input, 0, false, extra)));
        }
        for (const abs of [ethers.MaxUint256, ethers.MaxUint256 - 7n, ethers.MaxUint256 - 8n, 1n << 32n]) {
          const before = await outcome(() => method(false, valid, abs, true, extra));
          if (!size && key === "0x00000000" && abs > ethers.MaxUint256 - 8n) {
            expect(before.error).to.equal(ethers.concat(["0x4e487b71", ethers.toBeHex(0x11, 32)]));
          }
          expect(await outcome(() => method(true, valid, abs, true, extra))).to.deep.equal(before);
        }
      }
    }
  });

  it("retains full uint32 payload lengths when adding the header", async () => {
    const helper = await deploy("TestLeafFixed");
    for (let kind = 0; kind < leaves.length; kind++) {
      for (const length of [0n, 1n, 0xfffffff7n, 0xfffffff8n, 0xffffffffn]) {
        const data = ethers.concat([leaves[kind][1], ethers.toBeHex(length, 4)]);
        for (const optimized of [false, true]) {
          expect([...(await helper.leafBounds(optimized, kind, data))]).to.deep.equal([8n, length, length + 8n]);
        }
      }
    }
  });
});
