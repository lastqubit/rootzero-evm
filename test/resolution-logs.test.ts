import { expect } from "chai";
import { ethers } from "ethers";
import { deploy } from "./helpers/setup.js";
import { Keys, exactSpec, encodeBlock } from "./helpers/blocks.js";

describe("Resolution category logs", () => {
  it("preserves full-width keys, digests and explicit resolution status", async () => {
    const helper = await deploy("TestResolutionLogs");
    const spec = exactSpec(Keys.Resolution, 64);
    expect(Array.from(await helper.catalog())).deep.eq([Keys.Resolution, spec, 72n, spec >> 192n, "bytes32 key, bytes32 digest"]);
    for (const [key, digest] of [[ethers.ZeroHash, ethers.toBeHex(ethers.MaxUint256, 32)],
      [ethers.toBeHex(ethers.MaxUint256, 32), ethers.ZeroHash]]) {
      const block = encodeBlock(Keys.Resolution, ethers.concat([key, digest]));
      for (const resolved of [false, true]) {
        expect(await helper.publish.staticCall(key, digest, resolved)).eq(block);
        const receipt = await (await helper.publish(key, digest, resolved)).wait();
        expect(receipt.logs.map((log: any) => ({ topics: log.topics, data: log.data }))).deep.eq([
          { topics: [], data: ethers.concat(["0x09", key, digest, resolved ? "0x01" : "0x00"]) },
        ]);
      }
    }
  });

  it("removes resolution ABI announcements from Portal", async () => {
    const portal = await deploy("TestPortalRecoverHost", 0n);
    expect(portal.interface.getEvent("Resolved")).eq(null);
    expect(portal.interface.getEvent("Unresolved")).eq(null);
    expect(portal.interface.getEvent("EventAbi")).eq(null);
  });
});
