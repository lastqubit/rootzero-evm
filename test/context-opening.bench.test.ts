import { expect } from "chai";
import { ethers } from "ethers";
import { writeFileSync } from "node:fs";
import { deploy } from "./helpers/setup.js";
import { encodeBlock, encodeContextBlock, encodeBalanceBlock, Keys } from "./helpers/blocks.js";

async function outcome(helper: any, data: string) {
  try { return { value: Array.from(await helper.measure(data, 0, 19)).slice(1) }; }
  catch (error: any) {
    const revert = error.data ?? error.info?.error?.data;
    expect(revert).to.be.a("string");
    return { error: revert };
  }
}

describe("Context opening composition", function () {
  this.timeout(120_000);
  it("compares opening gas and exact valid results", async () => {
    const previous = await deploy("ContextOpeningPrevious"), shared = await deploy("ContextOpeningShared");
    const rows: any[] = [];
    const account = ethers.toBeHex(7, 32);
    for (const count of [0, 1, 2, 4, 16]) for (const mode of [0, 1, 2]) {
      const balance = encodeBalanceBlock(account, 123n);
      const state = mode === 1 ? "0x" : ethers.concat(Array(count).fill(balance));
      const input = mode === 0 ? "0x" : ethers.concat(Array(count).fill(balance));
      const data = encodeContextBlock(account, state, input);
      for (const allocate of [false, true]) {
        const key = BigInt(Keys.Balance);
        const descriptor = allocate ? (key << 160n) | (key << 128n) | (72n << 96n) | (72n << 64n) | (mode === 1 ? 0n : 64n << 56n) : 0n;
        const a = await previous.measure(data, descriptor, ethers.MaxUint256);
        const b = await shared.measure(data, descriptor, ethers.MaxUint256);
        expect(Array.from(b).slice(1)).deep.eq(Array.from(a).slice(1));
        rows.push({ count, mode, allocate, previous: Number(a[0]), shared: Number(b[0]), delta: Number(b[0] - a[0]) });
      }
    }
    console.table(rows.filter(r => r.count <= 1));
    writeFileSync(".npm-cache/context-opening-gas.json", JSON.stringify(rows, null, 2));
  });
  it("compares acceptance and revert selectors for malformed context boundaries", async () => {
    const previous = await deploy("ContextOpeningPrevious"), shared = await deploy("ContextOpeningShared");
    const valid = encodeContextBlock(ethers.toBeHex(7, 32), encodeBlock(Keys.Bytes, "0x1234"), "0xaabbcc");
    const vectors = [valid, ethers.concat([valid, "0x00"]), ethers.concat([valid, valid])];
    for (let n = 0; n < ethers.dataLength(valid); n++) vectors.push(ethers.dataSlice(valid, 0, n));
    const stateHeader = 40, inputHeader = 48 + ethers.dataLength(encodeBlock(Keys.Bytes, "0x1234"));
    for (const offset of [0, stateHeader, inputHeader]) {
      const wrong = ethers.getBytes(valid); wrong[offset] ^= 255; vectors.push(ethers.hexlify(wrong));
      for (const length of [0, 1, 7, 8, 32, 64, 72, 0xffffffff]) {
        const altered = ethers.getBytes(valid); altered.set(ethers.getBytes(ethers.toBeHex(length, 4)), offset + 4);
        vectors.push(ethers.hexlify(altered));
      }
    }
    const changed: any[] = [];
    for (const data of vectors) {
      const a = await outcome(previous, data), b = await outcome(shared, data);
      expect("value" in b, data).eq("value" in a);
      if ("value" in a) expect(b).deep.eq(a);
      else if (a.error !== b.error) changed.push({ data, previous: a.error, shared: b.error });
    }
    console.log({ cases: vectors.length, changedErrors: changed.length });
    writeFileSync(".npm-cache/context-opening-errors.json", JSON.stringify({ cases: vectors.length, changed }, null, 2));
  });
});
