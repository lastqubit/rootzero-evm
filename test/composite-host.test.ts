import { expect } from "chai";
import { deploy } from "./helpers/setup.js";
import { encodeHostAccount } from "./helpers/blocks.js";

describe("Composite Host", () => {
  it("deploys a host that mixes commands, peer entrypoints, and queries", async () => {
    const host = await deploy("TestCompositeHost", 0n);
    expect(await host.getAddress()).to.not.equal("0x0000000000000000000000000000000000000000");
    expect(await host.hostAccount()).to.equal(encodeHostAccount(await host.host()));
  });
});
