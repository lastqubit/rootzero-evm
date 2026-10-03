import { expect } from "chai";
import { ethers } from "ethers";
import { deploy } from "./helpers/setup.js";
import "./helpers/matchers.js";

describe("Entity-kind codes", () => {
  it("exports stable category-1 identifiers including Pool, Port, and Balance", async () => {
    const helper = await deploy("TestEventCodes");
    expect(Array.from(await helper.entityKinds())).to.deep.equal([
      0x20000000n, 0x20000001n, 0x20000002n, 0x20000003n, 0x20000004n,
      0x20000005n, 0x20000006n, 0x20000007n, 0x20000008n, 0x20000009n, 0x2000000an,
    ]);
  });

  for (const [method, action, entity, state] of [
    ["emitAddRoute", 4n, 0x20000005n, 0xa0000001n],
    ["emitRemoveRoute", 5n, 0x20000005n, 0xa0000000n],
    ["emitAllowAsset", 20n, 0x20000000n, 0xa0000001n],
    ["emitDenyAsset", 21n, 0x20000000n, 0xa0000000n],
  ] as const) {
    it(`packs ${method} and preserves it through the CODES codec`, async () => {
      const helper = await deploy("TestEventCodes");
      const codec = await deploy("TestCodesBlock");
      const account = ethers.toBeHex(1, 32);
      const subject = ethers.toBeHex(2, 32);
      const codes = action | (entity << 32n) | (state << 64n);
      await expect(helper[method](account, subject))
        .to.emit(helper, "Activity").withArgs(account, subject, 0n, codes);
      const [encoded] = await codec.encode(codes, 0);
      for (const execution of [false, true]) {
        expect(Array.from(await codec.decode(encoded, 40, execution)))
          .to.deep.equal([codes, 40n, 0n]);
      }
    });
  }
});
