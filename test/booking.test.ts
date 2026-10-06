import { expect } from "chai";
import { ethers } from "ethers";
import { deploy } from "./helpers/setup.js";
import { concat, encodeBookingBlock, exactSpec, Keys } from "./helpers/blocks.js";
import "./helpers/matchers.js";

describe("Booking block", () => {
  it("defines the canonical six-word schema and round trips structs through all writers", async () => {
    const host = await deploy("TestBooking");
    const spec = exactSpec(Keys.Booking, 192);
    expect(Array.from(await host.definition())).deep.eq([Keys.Booking, spec, spec >> 192n, 200n,
      "bytes32 from, bytes32 to, bytes32 liability, uint debt, bytes32 asset, uint amount"]);
    for (const amount of [0n, 1n, ethers.MaxUint256]) {
      const value = { from: ethers.toBeHex(11, 32), to: ethers.toBeHex(22, 32), asset: ethers.toBeHex(33, 32),
        amount, liability: ethers.toBeHex(44, 32), debt: ethers.MaxUint256 - amount };
      const encoded = encodeBookingBlock(value), pair = concat(encoded, encoded);
      expect(Array.from(await host.encode(value))).deep.eq([encoded, pair]);
      const decoded = await host.decode(pair, 400);
      expect(Array.from(decoded[0])).deep.eq([value.from, value.to, value.liability, value.debt, value.asset, value.amount]);
      expect(decoded[1]).eq(200n); expect(decoded[2]).eq(123n);
      expect(await host.bounce(pair)).eq(pair);
      await expect(host.decode(pair, 199)).revertedWithCustomError(host, "OutOfBounds");
      await expect(host.decode("0xffffffff" + encoded.slice(10), 200)).revertedWithCustomError(host, "InvalidBlock");
      await expect(host.decode(encoded.slice(0, 10) + "000000a0" + encoded.slice(18), 200)).revertedWithCustomError(host, "InvalidBlock");
    }
    expect(await host.bounce("0x")).eq("0x");
  });
});
