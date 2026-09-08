import { expect } from "chai";
import { ethers } from "ethers";
import { mkdirSync, writeFileSync } from "node:fs";
import { deploy } from "./helpers/setup.js";
import { encodeBlock, Keys } from "./helpers/blocks.js";

const word = ethers.toBeHex(33, 32);
const blob = (size: number) => "0x" + "ab".repeat(size);
function encode(name: string, input: string) {
  const child = encodeBlock(Keys.String, input);
  return name === "Label" ? encodeBlock(Keys.Label, ethers.concat([word, child]))
    : encodeBlock(Keys.Schema, ethers.concat([
      ethers.toBeHex(11, 32), child, name === "SchemaUnnamed" ? ethers.ZeroHash : word,
    ]));
}
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

describe("LABEL and SCHEMA optimization", function () {
  this.timeout(120_000);
  it("benchmarks factories and decoders, including dirty memory and unnamed schemas", async () => {
    const helper = await deploy("TestComposites");
    const rows: any[] = [];
    const coder = ethers.AbiCoder.defaultAbiCoder();
    for (const name of ["Label", "Schema", "SchemaUnnamed"]) {
      for (const size of [0, 1, 7, 8, 23, 24, 31, 32, 33, 256, 4096]) {
        const input = blob(size), encoded = encode(name, input);
        const factory = helper["factory" + name];
        const before = await factory(false, input, 0);
        const after = await factory(true, input, 0);
        expect(before.output).to.equal(encoded);
        expect(after.output).to.equal(encoded);
        expect(before.cleanTail && after.cleanTail).to.equal(true);
        expect(after.usedGas).to.be.lessThan(before.usedGas);
        rows.push({ operation: "create" + name, size, before: Number(before.usedGas),
          after: Number(after.usedGas), saved: Number(before.usedGas - after.usedGas) });
        const decoder = helper["decode" + (name === "Label" ? "Label" : "Schema")];
        const data = ethers.concat(["0xaabbcc", encoded, "0xdeadbeef"]);
        const oldDecoded = await decoder(false, data, 3, false);
        const newDecoded = await decoder(true, data, 3, false);
        const end = ethers.dataLength(encoded) + 3;
        // ABI encodes bytes and string identically; retain arbitrary non-UTF8 input.
        const expected = name === "Label" ? coder.encode(["bytes32", "bytes", "uint256"], [word, input, end])
          : coder.encode(["uint256", "bytes", "bytes32", "uint256"],
            [11, input, name === "SchemaUnnamed" ? ethers.ZeroHash : word, end]);
        expect(oldDecoded.output).to.equal(expected);
        expect(newDecoded.output).to.equal(expected);
        expect(newDecoded.usedGas).to.be.lessThan(oldDecoded.usedGas);
        rows.push({ operation: "unpack" + name, size, before: Number(oldDecoded.usedGas),
          after: Number(newDecoded.usedGas), saved: Number(oldDecoded.usedGas - newDecoded.usedGas) });
      }
    }
    mkdirSync(".npm-cache", { recursive: true });
    writeFileSync(".npm-cache/string-composite-results.json", JSON.stringify(rows, null, 2) + "\n");
    console.table(rows.filter(row => row.size === 0));
  });

  it("preserves malformed headers, truncation, trailing names, and absolute-position errors", async () => {
    const helper = await deploy("TestComposites");
    for (const name of ["Label", "Schema"]) {
      const method = helper["decode" + name];
      const encoded = encode(name, blob(3));
      const samples = [encoded, "0x", replace(encoded, 0, "0xffffffff"),
        replace(encoded, 40, Keys.Bytes), replace(encoded, 40, "0xffffffff")];
      for (const length of [0, 1, 7, 8, 31, 32, 39, 40, 42, 43, 44, 71, 72, 74, 75, 76, 0xffffffff]) {
        samples.push(replace(encoded, 4, ethers.toBeHex(length, 4)));
        samples.push(replace(encoded, 44, ethers.toBeHex(length, 4)));
      }
      for (let length = 0; length < ethers.dataLength(encoded); length++) {
        samples.push(ethers.dataSlice(encoded, 0, length));
      }
      for (const data of samples) {
        const before = await outcome(() => method(false, data, 0, false));
        expect(await outcome(() => method(true, data, 0, false))).to.deep.equal(before);
      }
      for (const abs of [ethers.MaxUint256, ethers.MaxUint256 - 7n, ethers.MaxUint256 - 71n, 1n << 32n]) {
        const before = await outcome(() => method(false, encoded, abs, true));
        expect(before.error).to.equal(ethers.id("InvalidBlock()").slice(0, 10));
        expect(await outcome(() => method(true, encoded, abs, true))).to.deep.equal(before);
      }
    }
  });

  it("retains payload-length limits and arithmetic-overflow errors in all factory overloads", async () => {
    const helper = await deploy("TestComposites");
    for (const name of ["Label", "Schema", "SchemaUnnamed"]) {
      const method = helper["factory" + name];
      // These factories bound the outer payload, rather than total encoded length.
      const overhead = name === "Label" ? 40n : 72n;
      for (const length of [(1n << 32n) - overhead, 1n << 32n, ethers.MaxUint256]) {
        const before = await outcome(() => method(false, "0x", length));
        expect(before.error).to.equal(length === ethers.MaxUint256
          ? ethers.concat(["0x4e487b71", ethers.toBeHex(0x11, 32)])
          : ethers.id("ValueOverflow()").slice(0, 10));
        expect(await outcome(() => method(true, "0x", length))).to.deep.equal(before);
      }
    }
  });
});
