import { expect } from "chai";
import { ethers } from "ethers";
import { deploy } from "./helpers/setup.js";
import { concat } from "./helpers/blocks.js";

describe("Absolute encoder cursor experiment", () => {
  it("rebases addresses on growth, preserves metadata and output, and retains scratch", async () => {
    const helper = await deploy("TestAbsoluteEncoderBuffer");
    for (const capacity of [0, 1, 17, 31, 32, 68, 256]) for (const count of [1, 4, 16]) {
      const [cur, base, output, padding] = await helper.inspect(capacity, count);
      expect((cur & 0xffffffffn) - base).eq(BigInt(17 * count));
      expect((cur >> 32n) & 0xffffffffn).gte(cur & 0xffffffffn);
      expect(cur >> 128n).eq(0xabcdefn);
      expect(output).eq(concat(...Array.from({ length: count }, (_, j) => "0x01020304000000000506070800000001" + ethers.toBeHex(j, 1).slice(2))));
      expect(padding).eq(ethers.ZeroHash);
    }
  });

  it("supports unused lazy writers and empty allocated writers", async () => {
    const helper = await deploy("TestAbsoluteEncoderBuffer");
    for (const capacity of [0, 1, 128]) for (const warm of [false, true]) {
      const [, output] = await helper.balances(ethers.ZeroHash, 0, 0, capacity, warm);
      expect(output).eq("0x");
    }
  });

  it("rejects ranges outside the uint32 address space before allocation", async () => {
    const helper = await deploy("TestAbsoluteEncoderBuffer");
    for (const size of [0xffffffffn, 1n << 32n, ethers.MaxUint256]) {
      let failed = false;
      try { await helper.overflow(size); } catch { failed = true; }
      expect(failed).eq(true);
    }
  });
});
