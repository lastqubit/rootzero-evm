import { expect } from "chai";
import { ethers } from "ethers";
import { writeFileSync } from "node:fs";
import { deploy } from "./helpers/setup.js";
import { encodeBalanceBlock, encodeContextBlock, Keys } from "./helpers/blocks.js";

describe("Default opening after scaled overloads", () => {
  it("compares default opening against frozen pre-scaling implementations", async () => {
    const previous = await deploy("ScaledOpeningPrevious"), current = await deploy("ScaledOpeningCurrent");
    const key = BigInt(Keys.Balance), account = ethers.toBeHex(9, 32), rows: any[] = [];
    for (const context of [false, true]) for (const scan of [false, true]) for (const count of [0, 1, 2, 4, 16]) {
      const stream = ethers.concat(Array(count).fill(encodeBalanceBlock(account, 7n)));
      const source = context ? encodeContextBlock(account, stream, "0x1234") : stream;
      for (const allocate of [false, true]) {
        const descriptor = allocate ? (key << 160n) | (key << 128n) | ((scan ? 0n : 72n) << 96n)
          | (72n << 64n) | (context ? 64n << 56n : 0n) : 0n;
        const a = await previous.measure(source, descriptor, context), b = await current.measure(source, descriptor, context);
        expect(Array.from(b).slice(1)).deep.eq(Array.from(a).slice(1));
        expect(b.used, `default opening: context=${context}, scan=${scan}, count=${count}, allocate=${allocate}`).eq(a.used);
        rows.push({ context, scan, count, allocate, previous: Number(a.used), current: Number(b.used), delta: Number(b.used - a.used) });
      }
    }
    console.table(rows.filter(r => r.count <= 1 && r.allocate));
    writeFileSync(".npm-cache/scaled-opening-gas.json", JSON.stringify(rows, null, 2));
  });
});
