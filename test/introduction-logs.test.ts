import { expect } from "chai";
import { ethers } from "ethers";
import { deploy } from "./helpers/setup.js";
import { exactSpec, encodeBlock, Keys } from "./helpers/blocks.js";
import { HostIntroduce, decodeIntroductionLog } from "./helpers/introduction-logs.js";

describe("Introduction block logs", () => {
  it("preserves the canonical layout and full-width scalar fields", async () => {
    const helper = await deploy("TestIntroductionLogs");
    const spec = exactSpec(Keys.Introduction, 96);
    expect(Array.from(await helper.catalog())).deep.eq([spec, 104n, spec >> 192n, "uint peer, bytes32 origin, uint blocknum"]);
    for (const value of [0n, ethers.MaxUint256]) {
      const origin = ethers.toBeHex(value, 32);
      const block = encodeBlock(Keys.Introduction, ethers.concat([origin, origin, origin]));
      expect(await helper.publish.staticCall(value, origin, value)).eq(block);
      const receipt = await (await helper.publish(value, origin, value)).wait();
      expect(receipt.logs.length).eq(1);
      expect(receipt.logs[0].topics).deep.eq([]);
      expect(receipt.logs[0].data).eq(ethers.concat([ethers.toBeHex(HostIntroduce, 32), block]));
      expect(decodeIntroductionLog(receipt.logs[0])).deep.eq({ peer: value, origin, blocknum: value });
    }
  });
});
