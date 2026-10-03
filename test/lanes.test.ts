import { expect } from "chai";
import { ethers } from "ethers";
import { deploy } from "./helpers/setup.js";
import { exactSpec, rangedSpec, Keys } from "./helpers/blocks.js";
import "./helpers/matchers.js";

describe("Endpoint lanes", () => {
  it("preserves specs and all four code slots without overlap", async () => {
    const helper = await deploy("TestLanes");
    for (const spec of [0n, exactSpec(Keys.Balance, 64), rangedSpec(Keys.Bytes, 0, 0, 0xffffff)]) {
      for (const codes of [0n, 1n, 1n << 96n, (1n << 128n) - 1n]) {
        const result = await helper.inspect(spec, codes);
        expect(result.lane).eq(spec | codes);
        expect(result.spec).eq(spec);
        expect(result.value).eq(codes);
        expect(result.size).eq(spec === 0n ? 0n : 8n + ((spec >> 136n) & 0xffffffn));
      }
    }
    await expect(helper.inspect(0, 1n << 128n)).to.be.revertedWithCustomError(helper, "ValueOverflow");
    await expect(helper.inspect(0, ethers.MaxUint256)).to.be.revertedWithCustomError(helper, "ValueOverflow");
    await expect(helper.inspect(exactSpec(Keys.Balance, 64) | 1n, 0)).to.be.revertedWithCustomError(helper, "ValueOverflow");
  });
});
