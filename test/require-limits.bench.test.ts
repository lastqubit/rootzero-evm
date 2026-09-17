import { expect } from "chai";
import { deploy } from "./helpers/setup.js";
import { concat, encodeLimitsBlock } from "./helpers/blocks.js";

describe("Direct calldata limits benchmark", () => {
  it("compares direct checks with decoding limits for an existing position", async () => {
    const helper = await deploy("TestRequireLimits");
    const rows: { count: number; direct: number; decoded: number; saved: number }[] = [];
    for (const count of [1, 8, 32]) {
      const input = concat(...Array(count).fill(encodeLimitsBlock(100n, 40n)));
      const direct = await helper.measureDirect(input, 100n, 40n);
      const decoded = await helper.measureDecoded(input, 100n, 40n);
      expect(direct[1]).to.equal(decoded[1]);
      rows.push({ count, direct: Number(direct[0]), decoded: Number(decoded[0]), saved: Number(decoded[0] - direct[0]) });
    }
    console.table(rows);
  });
});
