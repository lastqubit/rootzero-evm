import { expect } from "chai";
import { ethers } from "ethers";
import { deploy } from "./helpers/setup.js";
import { Keys, encodeBalanceBlock, encodeOutputBlock } from "./helpers/blocks.js";

describe("Output prefix and logical capacity", () => {
  it("publishes Output as an unbounded stream container", async () => {
    const helper = await deploy("TestOutputCapacity");
    expect(Array.from(await helper.catalog())).deep.eq([Keys.Output, (BigInt(Keys.Output) << 224n) | (128n << 136n), ""]);
  });
  it("fills the descriptor's exact capacity without moving the buffer and grows only on overflow", async () => {
    const helper = await deploy("TestOutputCapacity");
    for (const count of [0, 1, 2, 4, 16, 64]) {
      const input = ethers.concat(Array.from({ length: count }, (_, i) => encodeBalanceBlock(ethers.toBeHex(i + 1, 32), BigInt(i))));
      for (const extra of [false, true]) {
        const r = await helper.exact.staticCall(input, extra);
        expect(r.initialCapacity).eq(BigInt(count * 72));
        expect(r.initialFootprint).eq(((BigInt(count * 72) + 31n) & ~31n) + 96n);
        expect(r.sameBuffer).eq(!extra);
        if (extra) expect(r.finalCapacity).gt(r.initialCapacity);
        else expect(r.finalCapacity).eq(r.initialCapacity);
        const expected = extra ? ethers.concat([input, encodeBalanceBlock(ethers.toBeHex(99, 32), 123n)]) : input;
        expect(r.output).eq(expected);
        const receipt = await (await helper.exact(input, extra)).wait();
        expect(receipt.logs.map((l: any) => [l.topics, l.data])).deep.eq([[[], ethers.concat([ethers.toBeHex(123, 32), encodeOutputBlock(expected)])]]);
      }
    }
  });
});
