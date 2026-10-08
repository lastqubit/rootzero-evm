import { expectInputLog, expectAccessLogs } from "./helpers/scoped-logs.js";
import { expect } from "chai";
import { ethers } from "ethers";
import { commandId, deploy, getSigner, hostId } from "./helpers/setup.js";
import { exactSpec, rangedSpec, encodeBlock, Keys, encodeAccountBlock, encodeContextBlock, encodeNodeBlock, encodeUserAccount } from "./helpers/blocks.js";
import "./helpers/matchers.js";

describe("Host access and guardian logs", () => {
  for (const kind of ["Node", "Guardian"] as const) {
    it(`${kind} publishes its policy and handles repeated and empty operations`, async () => {
      const commander = await (await getSigner()).getAddress();
      const host = await deploy("TestHost", await hostId(commander));
      const account = await host.getAdminAccount();
      const target = await (await getSigner(4)).getAddress();
      const subject = kind === "Node" ? await hostId(target) : encodeUserAccount(target);
      const block = kind === "Node" ? encodeNodeBlock(subject as bigint) : encodeAccountBlock(subject as string);
      expect(host.interface.getEvent("EventAbi")).eq(null);
      expect(host.interface.getEvent(kind)).eq(null);
      for (const active of [true, true, false, false]) {
        const method = kind === "Node" ? (active ? "authorize" : "unauthorize") : (active ? "appoint" : "dismiss");
        const id = await commandId(`${method}(bytes)`, host, 2n);
        await expect(host.deploymentTransaction()).to.emitEndpoint(host).withArgs(id, 0n, exactSpec(kind === "Node" ? Keys.Node : Keys.Account, 32), 0n);
        for (const input of ["0x", block, ethers.concat([block, block])]) {
          if (kind === "Node") {
            const changed = input !== "0x" && (await host.isAuthorized(subject)) !== active;
            await expectAccessLogs(host[method](encodeContextBlock(account, "0x", input)), changed ? [subject as bigint] : [], active);
          } else {
            await expectInputLog(host[method](encodeContextBlock(account, "0x", input)), host, method, input);
          }
          if (input !== "0x") expect(kind === "Node" ? await host.isAuthorized(subject) : await host.isGuardianAddress(target)).eq(active);
        }
      }
    });
  }
});

describe("Asset block logs", () => {
  const logs = (receipt: any) => receipt.logs.map((log: any) => ({ topics: log.topics, data: log.data }));

  it("publishes the canonical preimage schema without legacy ABI announcements", async () => {
    const emitter = await deploy("TestAssetLogs");
    expect(emitter.interface.getEvent("Asset")).eq(null);
    expect(emitter.interface.getEvent("AssetPreimage")).eq(null);
    expect((await emitter.deploymentTransaction().wait()).logs).deep.eq([]);
    expect(Array.from(await emitter.catalog())).deep.eq([
      rangedSpec(Keys.AssetPreimage, 40, 0, 256), "bytes32 asset, #bytes as preimage",
    ]);
  });

  it("preserves full-width asset IDs and complete unpadded preimages", async () => {
    const emitter = await deploy("TestAssetLogs");
    for (const asset of [ethers.ZeroHash, ethers.toBeHex(ethers.MaxUint256, 32)]) {
      for (const length of [0, 1, 3, 31, 32, 33, 65, 256]) {
        const preimage = "0x" + "ab".repeat(length);
        const block = encodeBlock(Keys.AssetPreimage, ethers.concat([asset, encodeBlock(Keys.Bytes, preimage)]));
        expect(await emitter.emitPreimage.staticCall(asset, preimage)).eq(block);
        const receipt = await (await emitter.emitPreimage(asset, preimage)).wait();
        expect(logs(receipt)).deep.eq([{ topics: [], data: ethers.concat(["0x03", asset, block]) }]);
      }
    }
  });

});
