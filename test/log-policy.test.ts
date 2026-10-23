import { expect } from "chai";
import { deploy } from "./helpers/setup.js";

describe("Logging hints", () => {
  it("uses standalone lane bits 3-5", async () => {
    const helper = await deploy("TestLogFlags");
    expect(Array.from(await helper.logFlags())).deep.eq([8n, 16n, 32n]);
  });
});
