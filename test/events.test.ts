import { expectInputLog } from "./helpers/scoped-logs.js";
import { expect } from "chai";
import { ethers } from "ethers";
import { commandId, deploy, getSigner, hostId } from "./helpers/setup.js";
import { exactSpec, rangedSpec, encodeBlock, Keys, encodeAccountBlock, encodeContextBlock, encodeNodeBlock, encodeUserAccount } from "./helpers/blocks.js";
import "./helpers/matchers.js";

describe("Host-scoped access input logs", () => {
  for (const kind of ["Node", "Guardian"] as const) {
    it(`${kind} publishes scoped lanes and logs complete repeated and empty operations`, async () => {
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
        const action = kind === "Node" ? (active ? 16n : 17n) : (active ? 18n : 19n);
        const state = active ? 0xa0000001n : 0xa0000000n;
        const codes = kind === "Node" ? 0x20000002n | (action << 32n) | (state << 64n)
          : 0x20000002n | (0x20000007n << 32n) | (action << 64n) | (state << 96n);
        const id = await commandId(`${method}(bytes)`, host, 2n);
        await expect(host.deploymentTransaction()).to.emitEndpoint(host).withArgs(id, 0n, exactSpec(kind === "Node" ? Keys.Node : Keys.Account, 32) | codes, 0n);
        for (const input of ["0x", block, ethers.concat([block, block])]) {
          await expectInputLog(host[method](encodeContextBlock(account, "0x", input)), host, method, input);
          if (input !== "0x") expect(kind === "Node" ? await host.isAuthorized(subject) : await host.isGuardianAddress(target)).eq(active);
        }
      }
    });
  }
});

describe("Asset block logs", () => {
  const hostScope = 0x20000002n;
  const assetAnnotate = 0x20000000n | (8n << 32n);
  const expectedLog = (codes: bigint, block: string) => ({
    topics: [], data: ethers.concat([ethers.toBeHex(codes, 32), block]),
  });
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
        expect(logs(receipt)).deep.eq([expectedLog(assetAnnotate, block)]);
      }
    }
  });

  it("records scoped lifecycle actions and resulting state without topics", async () => {
    const emitter = await deploy("TestAssetLogs");
    const asset = ethers.toBeHex(123n, 32);
    for (const [action, state] of [[20n, 0xa0000001n], [21n, 0xa0000000n],
      [1n, 0xa0000000n], [2n, 0xa0000001n]]) {
      const codes = hostScope | (action << 32n) | (state << 64n);
      const receipt = await (await emitter.emitAsset(asset, codes)).wait();
      expect(logs(receipt)).deep.eq([expectedLog(codes, encodeBlock(Keys.Asset, asset))]);
      expect(receipt.logs[0].address.toLowerCase()).eq((await emitter.getAddress()).toLowerCase());
    }
  });

  it("can name another host explicitly and preserves a complete eight-slot code word", async () => {
    const emitter = await deploy("TestAssetLogs");
    const host = ethers.MaxUint256, asset = ethers.toBeHex(ethers.MaxUint256, 32);
    const codes = [hostScope, 2n, 0xa0000001n, 4n, 5n, 6n, 7n, 8n]
      .reduce((word, code, i) => word | (code << BigInt(32 * i)), 0n);
    const receipt = await (await emitter.emitHostAsset(host, asset, codes)).wait();
    expect(logs(receipt)).deep.eq([expectedLog(codes,
      encodeBlock(Keys.HostAsset, ethers.concat([ethers.toBeHex(host, 32), asset])))]);
    expect(logs(await (await emitter.emitAsset(asset, codes)).wait()))
      .deep.eq([expectedLog(codes, encodeBlock(Keys.Asset, asset))]);
  });
});
