import { expect } from "chai";
import { ethers } from "ethers";
import { deploy } from "./helpers/setup.js";
import { encodeBlock } from "./helpers/blocks.js";
import { decoderLayouts } from "./helpers/decoder-layouts.js";

async function rejects(call: Promise<unknown>, name: string) {
  let data: string | undefined;
  try { await call; } catch (error: any) { data = error.data ?? error.info?.error?.data; }
  expect(data).eq(ethers.id(name + "()").slice(0, 10));
}

describe("Execution fixed cursor decoders", () => {
  it("decodes all fields and advances only the selected lane, preserving bounds and metadata", async () => {
    const helper = await deploy("TestExecutionDecoders");
    for (const [kind, layout] of decoderLayouts.entries()) {
      const key = ethers.id("#" + layout.name[0].toLowerCase() + layout.name.slice(1)).slice(0, 10);
      const payload = ethers.concat(Array.from({ length: layout.words }, (_, i) => ethers.toBeHex(ethers.MaxUint256 - BigInt(i), 32)));
      const block = encodeBlock(key, payload);
      for (const suffix of ["0x", block]) {
        const source = ethers.concat([block, suffix]);
        const length = ethers.dataLength(source);
        const result = await helper.inspect(kind, source, length, false);
        const previous = await helper.inspect(kind, source, length, true);
        expect(result.data, layout.name).eq(payload);
        expect(result.data).eq(previous.data);
        const original = result.base | ((result.base + BigInt(length)) << 32n) | (0xa5n << 64n);
        const advanced = original + BigInt(ethers.dataLength(block));
        expect(result.input).eq(layout.state ? original : advanced);
        expect(result.state).eq(layout.state ? advanced : original);
      }
      for (const length of [0, 7, 8, ethers.dataLength(block) - 1]) {
        await rejects(helper.inspect(kind, block, length, false), "OutOfBounds");
      }
      await rejects(helper.inspect(kind, encodeBlock("0xffffffff", payload), ethers.dataLength(block), false), "InvalidBlock");
      const wrongLength = encodeBlock(key, ethers.concat([payload, "0x00"]));
      await rejects(helper.inspect(kind, wrongLength, ethers.dataLength(wrongLength), false), "InvalidBlock");
      await rejects(helper.inspect(kind, wrongLength, 0, false), "InvalidBlock");
    }
  });
});

describe("Execution composite cursor decoders", () => {
  it("returns clean payload cursors, validates child shape, and consumes the parent exactly once", async () => {
    const helper = await deploy("TestExecutionCompositeDecoders");
    const names = ["bytes", "string", "relay", "annotation", "label", "schema", "context", "step", "call", "dispatch", "recover"];
    const wordCounts = [0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 3];
    const key = (name: string) => ethers.id("#" + name).slice(0, 10);
    for (const [kind, name] of names.entries()) for (const size of [0, 1, 33]) {
      const count = wordCounts[kind];
      const values = Array.from({ length: count }, (_, i) => ethers.MaxUint256 - BigInt(i));
      const prefix = ethers.concat(values.map(value => ethers.toBeHex(value, 32)));
      const data = "0x" + "ab".repeat(size);
      const two = kind === 2 || kind === 6;
      const childKey = key(kind === 4 || kind === 5 ? "string" : "bytes");
      const children = kind < 2 ? data : ethers.concat([encodeBlock(childKey, data), ...(two ? [encodeBlock(childKey, "0xcdef")] : [])]);
      const block = encodeBlock(key(name), ethers.concat([prefix, children]));
      const source = ethers.concat([block, encodeBlock(key("bytes"), "0x12")]);
      const length = ethers.dataLength(source);
      const result = await helper.inspect(kind, source, length);
      expect(Array.from(result[0])).deep.eq([...values, ...Array(3 - count).fill(0n)]);
      const start = result.base + BigInt(8 + count * 32 + (kind < 2 ? 0 : 8));
      expect(result.firstCur).eq(start | ((start + BigInt(size)) << 32n));
      if (two) {
        const second = start + BigInt(size + 8);
        expect(result.secondCur).eq(second | ((second + 2n) << 32n));
      } else expect(result.secondCur).eq(0n);
      expect(result.input).eq((result.base + BigInt(ethers.dataLength(block))) | ((result.base + BigInt(length)) << 32n) | (0xa5n << 64n));
      expect(result.state).eq(0x12345678n);
      await rejects(helper.inspect(kind, source, ethers.dataLength(block) - 1), "OutOfBounds");
      await rejects(helper.inspect(kind, encodeBlock("0xffffffff", ethers.concat([prefix, children])), ethers.dataLength(block)), "InvalidBlock");
      if (kind >= 2) {
        for (const body of ["0x", prefix, ethers.concat([prefix, encodeBlock("0xffffffff", data)]), ethers.concat([prefix, children, "0x00"])]) {
          const malformed = encodeBlock(key(name), body);
          await rejects(helper.inspect(kind, malformed, ethers.dataLength(malformed)), "InvalidBlock");
        }
      }
    }
  });
});
