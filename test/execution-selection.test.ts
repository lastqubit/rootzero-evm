import { expect } from "chai";
import { ethers } from "ethers";
import { deploy } from "./helpers/setup.js";
import { concat, encodeBlock, exactSpec, Keys } from "./helpers/blocks.js";
async function rejects(call: Promise<unknown>, name: string) {
  let data: string | undefined;
  try { await call; } catch (error: any) { data = error.data ?? error.info?.error?.data; }
  expect(data).eq(ethers.id(name + "()").slice(0, 10));
}

describe("Execution packed block selection", () => {
  it("consumes parents, returns clean bounded children, and preserves input metadata and state", async () => {
    const helper = await deploy("TestExecutionSelection");
    for (let mode = 0; mode <= 14; mode++) for (const size of [0, 1, 32, 65]) {
      const exact = [3, 8, 12, 13, 14].includes(mode);
      const block = encodeBlock(Keys.Bytes, "0x" + "ab".repeat(size));
      const source = exact ? block : concat(block, encodeBlock(Keys.String, "0x12"));
      const length = ethers.dataLength(source);
      const amount = Math.floor(size / 2);
      const [abs, selected, input, state, base] = await helper.inspect(source, length, exactSpec(Keys.Bytes, size), amount, mode);
      const blockEnd = base + BigInt(size + 8);
      const start = base + BigInt(mode < 4 ? 8 + amount : (mode <= 8 || mode === 13) ? 0 : 8);
      expect(selected).eq(start | (blockEnd << 32n));
      expect(selected >> 64n).eq(0n);
      expect(abs).eq(mode < 4 ? base + 8n : 0n);
      expect(input).eq(blockEnd | ((base + BigInt(length)) << 32n) | (0xa5n << 64n));
      expect(state).eq(0x12345678n);
    }
  });

  it("rejects truncation, schema mismatch, oversized prefixes, and trailing bytes in exact selectors", async () => {
    const helper = await deploy("TestExecutionSelection");
    const block = encodeBlock(Keys.Bytes, "0x" + "ab".repeat(32));
    const spec = exactSpec(Keys.Bytes, 32);
    for (let mode = 0; mode <= 14; mode++) {
      const exact = [3, 8, 12, 13, 14].includes(mode);
      for (const length of [0, 7, 8, 39]) {
        await rejects(helper.inspect(block, length, spec, 0, mode), exact ? "InvalidBlock" : "OutOfBounds");
      }
      if (mode !== 4) await rejects(helper.inspect(block, 40, exactSpec(Keys.String, 32), 0, mode), "InvalidBlock");
      if (mode < 4) for (const amount of [33n, ethers.MaxUint256]) {
        await rejects(helper.inspect(block, 40, spec, amount, mode), "InvalidBlock");
      }
      if (exact) await rejects(helper.inspect(concat(block, block), 80, spec, 0, mode), "InvalidBlock");
    }
  });
});
