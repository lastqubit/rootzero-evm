import { expect } from "chai";
import { deploy } from "./helpers/setup.js";
import "./helpers/matchers.js";

describe("Cursor consumption primitives", () => {
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
