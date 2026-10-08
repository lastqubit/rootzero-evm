import { expect } from "chai";
import { deploy } from "./helpers/setup.js";

describe("Logging flags", () => {
  it("includes Execution in each lane flag", async () => {
    const helper = await deploy("TestLogFlags");
    expect(Array.from(await helper.logFlags())).deep.eq([4n, 12n, 20n, 36n]);
  });
});
