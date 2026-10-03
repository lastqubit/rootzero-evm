import { expect } from "chai";
import { ethers } from "ethers";
import { deploy } from "./helpers/setup.js";
import { encodeBalanceBlock, encodeContextBlock, Keys } from "./helpers/blocks.js";
import "./helpers/matchers.js";

const account = ethers.toBeHex(9, 32);
function fixture(count: number, context: boolean, scan = false, outputSize = 72n) {
  const stream = ethers.concat(Array(count).fill(encodeBalanceBlock(account, 7n)));
  const source = context ? encodeContextBlock(account, stream, "0x1234") : stream;
  const key = BigInt(Keys.Balance);
  const descriptor = (key << 224n) | ((scan ? 0n : 72n) << 192n)
    | (outputSize << 160n) | (context ? 1n : 0n);
  return { source, descriptor };
}

describe("Scaled execution opening", () => {
  let helper: any;
  before(async () => { helper = await deploy("TestScaledOpening"); });
  it("scales fixed and scanned hints once before allocation, with unchanged source cursors", async () => {
    for (const context of [false, true]) for (const scan of [false, true]) for (const count of [0, 1, 3]) {
      const f = fixture(count, context, scan);
      for (const [n, d] of [[0n, 1n], [1n, 1n], [2n, 1n], [1n, 2n], [1n, 5n], [3n, 2n]]) {
        const r = await helper.inspect(f.source, f.descriptor, n, d, context);
        const capacity = BigInt(count) * 72n * n / d;
        expect(r.capacity).eq(capacity);
        expect(r.bufferSize).eq(((capacity + 31n) & ~31n) + 32n);
        expect(r.account).eq(context ? account : ethers.ZeroHash);
        expect(r.budget).eq(99n);
        expect(r.inputCur >> 64n).eq(0n); expect(r.stateCur >> 64n).eq(0n);
        const length = (cur: bigint) => (cur >> 32n) - (cur & 0xffffffffn);
        expect(length(r.inputCur)).eq(context ? 2n : BigInt(count * 72));
        expect(length(r.stateCur)).eq(context ? BigInt(count * 72) : 0n);
        // A one-block descriptor with this output size allocates the same final capacity.
        const exact = fixture(1, context, false, capacity);
        const unscaled = await helper.inspect(exact.source, exact.descriptor, 1, 1, context);
        expect(r.footprint).eq(unscaled.footprint);
      }
    }
  });
  it("rejects zero denominators, product overflow, and final capacity overflow", async () => {
    for (const context of [false, true]) {
      for (const count of [0, 1]) {
        const f = fixture(count, context);
        await expect(helper.inspect(f.source, f.descriptor, 0, 0, context)).revertedWithCustomError(helper, "ZeroAmount");
      }
      const f = fixture(1, context);
      for (const [n, d] of [[ethers.MaxUint256, 1n], [ethers.MaxUint256, ethers.MaxUint256], [0x100000000n, 1n]]) {
        await expect(helper.inspect(f.source, f.descriptor, n, d, context)).revertedWithCustomError(helper, "ValueOverflow");
      }
      const empty = fixture(0, context);
      expect((await helper.inspect(empty.source, empty.descriptor, ethers.MaxUint256, 1, context)).capacity).eq(0n);
      const huge = fixture(2, context, false, 0xffffffffn);
      expect((await helper.inspect(huge.source, huge.descriptor, 1, 0xffffffffn, context)).capacity).eq(2n);
    }
  });
  it("grows past reduced hints and produces identical encoded output", async () => {
    const expected = ethers.concat(Array.from({ length: 4 }, (_, i) => encodeBalanceBlock(ethers.toBeHex(1, 32), BigInt(i + 1))));
    for (const context of [false, true]) for (const [n, d] of [[0, 1], [1, 2], [3, 1]]) {
      const f = fixture(1, context);
      expect(await helper.write(f.source, f.descriptor, n, d, context, 4)).eq(expected);
    }
  });
  it("still validates context shape before opening the output writer", async () => {
    const f = fixture(1, true);
    for (const source of ["0x", ethers.concat([f.source, "0x00"]), ethers.dataSlice(f.source, 0, 20)]) {
      await expect(helper.inspect(source, f.descriptor, 1, 1, true)).revertedWithCustomError(helper, "InvalidBlock");
    }
  });
});
