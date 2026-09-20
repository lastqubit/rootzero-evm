import {expect} from "chai";
import {ethers} from "ethers";
import {commandId, deploy, getSigner, hostId, portId} from "./helpers/setup.js";
import {concat, encodeAssetBlock, endpointDescriptor, Keys} from "./helpers/blocks.js";
import "./helpers/matchers.js";

describe("Singular asset endpoints", () => {
  async function setup() {
    return deploy("TestAssetEndpoints", await hostId(await (await getSigner()).getAddress()),
      await hostId(await (await getSigner(1)).getAddress()));
  }

  it("publishes singular command and port selectors in endpoint discovery", async () => {
    const host = await setup();
    for (const method of ["allowAsset", "denyAsset", "portAllowAsset", "portDenyAsset"]) {
      const admin = !method.startsWith("port");
      const id = admin ? await commandId(`${method}(bytes)`, host, 2n) : await portId(`${method}(bytes)`, host);
      const descriptor = endpointDescriptor({input: Keys.Asset, inputHint: 32, admin});
      await expect(host.deploymentTransaction()).to.emit(host, "Endpoint").withArgs(await host.host(), id, descriptor);
    }
  });

  it("keeps peer authorization and batching on the renamed ports", async () => {
    const host = await setup();
    const assets = [ethers.toBeHex(1n, 32), ethers.toBeHex(2n, 32)];
    const input = concat(...assets.map(encodeAssetBlock));
    const peer = host.connect(await getSigner(1)) as any;
    await peer.portAllowAsset(input);
    for (const asset of assets) expect(await host.allowed(asset)).to.equal(true);
    const stranger = host.connect(await getSigner(2)) as any;
    await expect(stranger.portAllowAsset(input)).to.be.revertedWithCustomError(host, "AccessDenied");
    await expect(stranger.portDenyAsset(input)).to.be.revertedWithCustomError(host, "AccessDenied");
    await peer.portDenyAsset(input);
    for (const asset of assets) expect(await host.allowed(asset)).to.equal(false);
    for (const method of ["portAllowAsset", "portDenyAsset"]) {
      expect(Array.from(await peer[method].staticCall("0x"))).to.deep.equal(["0x", 0n]);
    }
  });
});
