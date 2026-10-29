import { expect } from "chai";
import { ethers } from "ethers";
import { deploy } from "./helpers/setup.js";
import { Keys } from "./helpers/blocks.js";

describe("PortRequest catalog entry", () => {
  it("reserves #portRequest with a port word and an INPUT child", async () => {
    const helper = await deploy("TestPortRequestCatalog");
    expect(Keys.PortRequest).eq(ethers.dataSlice(ethers.id("#portRequest"), 0, 4));
    expect(Array.from(await helper.catalog())).deep.eq([
      Keys.PortRequest, (BigInt(Keys.PortRequest) << 224n) | (40n << 192n) | (256n << 136n), "uint port, #input",
    ]);
  });

  it("accepts a port word plus an INPUT header and anything longer", async () => {
    const helper = await deploy("TestPortRequestCatalog");
    expect(await helper.accepts(39n)).to.be.false;
    expect(await helper.accepts(40n)).to.be.true;
    expect(await helper.accepts(4096n)).to.be.true;
  });
});
