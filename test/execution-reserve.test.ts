import { expect } from "chai";
import { deploy } from "./helpers/setup.js";

describe("Execution raw reservations", () => {
  it("preserves written bytes and metadata across exact capacity, scratch writes, and growth", async () => {
    const helper = await deploy("TestExecutionReserve");
    for (const keep of [1, 8, 31, 32]) for (const count of [0, 1, 4]) {
      for (const capacity of [0, keep * count]) {
        const [output, metadata] = await helper.write.staticCall(capacity, keep, count);
        expect(output).eq("0x" + "ff".repeat(keep * count));
        expect(metadata).eq(0xabcdefn);
      }
    }
  });
});
