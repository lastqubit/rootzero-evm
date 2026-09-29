import { expect } from "chai";
import { ethers } from "ethers";
import { deploy } from "./helpers/setup.js";
import "./helpers/matchers.js";

describe("Cursor consumption primitives", () => {
  it("takes bounded raw ranges with clean children and preserves parent metadata", async () => {
    const helper = await deploy("TestCursorConsumption");
    for (const [start, end] of [[0n, 0n], [0n, 100n], [17n, 100n], [0n, 0xffffffffn], [0xfffffffen, 0xffffffffn]]) {
      for (const metadata of [0n, ethers.MaxUint256 & ~((1n << 64n) - 1n)]) {
        const cur = start | (end << 32n) | metadata;
        for (const amount of [0n, (end - start) / 2n, end - start]) {
          const [child, next] = await helper.take(cur, amount);
          expect(child).eq(start | ((start + amount) << 32n));
          expect(next).eq((start + amount) | (end << 32n) | metadata);
        }
        for (const amount of [end - start + 1n, ethers.MaxUint256]) {
          await expect(helper.take(cur, amount)).revertedWithCustomError(helper, "OutOfBounds");
        }
      }
    }
  });

  it("requires exact exhaustion, including zero and empty ranges", async () => {
    const helper = await deploy("TestCursorConsumption");
    for (const end of [0n, 17n, 0xffffffffn]) {
      await helper.expectEnd(end | (end << 32n));
    }
    for (const [start, end] of [[0n, 1n], [20n, 21n], [21n, 20n]]) {
      await expect(helper.expectEnd(start | (end << 32n))).revertedWithCustomError(helper, "UnconsumedData");
    }
  });
  it("advances directly to the end without changing the boundary", async () => {
    const helper = await deploy("TestCursorConsumption");
    for (const [start, end] of [[0n, 0n], [0n, 100n], [99n, 100n], [0xfffffffen, 0xffffffffn]]) {
      const cur = start | (end << 32n);
      const next = await helper.exhaust(cur);
      expect(next).eq(end | (end << 32n));
      expect(await helper.exhaust(next)).eq(next);
    }
  });
});
