import { expect } from "chai";
import { ethers } from "ethers";
import { deploy } from "./helpers/setup.js";
import { concat, encodeAccountBalanceBlock, exactSpec, Keys } from "./helpers/blocks.js";
import "./helpers/matchers.js";

describe("AccountBalance block", () => {
  it("defines the canonical three-word schema and round trips structs through all writers", async () => {
    const host = await deploy("TestAccountBalance");
    const spec = exactSpec(Keys.AccountBalance, 96);
    expect(Array.from(await host.definition())).deep.eq([Keys.AccountBalance, spec, spec >> 192n, 104n,
      "bytes32 account, bytes32 asset, uint amount"]);
    for (const amount of [0n, 1n, ethers.MaxUint256]) {
      const value = { account: ethers.toBeHex(11, 32), asset: ethers.toBeHex(22, 32), amount };
      const encoded = encodeAccountBalanceBlock(value.account, value.asset, value.amount), pair = concat(encoded, encoded);
      expect(Array.from(await host.encode(value))).deep.eq([encoded, pair]);
      const decoded = await host.decode(pair, 208);
      expect(Array.from(decoded[0])).deep.eq([value.account, value.asset, value.amount]);
      expect(decoded[1]).eq(104n); expect(decoded[2]).eq(123n);
      expect(await host.bounce(pair)).eq(pair);
      await expect(host.decode(pair, 103)).revertedWithCustomError(host, "OutOfBounds");
      await expect(host.decode("0xffffffff" + encoded.slice(10), 104)).revertedWithCustomError(host, "InvalidBlock");
      await expect(host.decode(encoded.slice(0, 10) + "00000040" + encoded.slice(18), 104)).revertedWithCustomError(host, "InvalidBlock");
    }
    expect(await host.bounce("0x")).eq("0x");
  });
});
