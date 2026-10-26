import { expect } from "chai";
import { ethers } from "ethers";
import { deploy, getSigner, hostId, portId } from "./helpers/setup.js";
import { concat, encodeEntityBlock, endpointSpecs, Keys } from "./helpers/blocks.js";
import { expectTrustLogs } from "./helpers/scoped-logs.js";
import "./helpers/matchers.js";

const CHECK_TRUST = ethers.id("checkTrust()").slice(0, 10);

describe("Trust registry and endorsement", () => {
  // Opaque asset IDs (representation 0x02, category Asset 0x03); node IDs are rejected by the ports.
  const asset = (0x0203n << 240n) | 0x1001n;
  const other = (0x0203n << 240n) | 0x1002n;
  let host: any;
  let peer: any;

  beforeEach(async () => {
    // The host is its own commander here, so Runtime checks call its own registry.
    host = await deploy("TestTrustEndpoints", 0n, await hostId(await (await getSigner(1)).getAddress()));
    peer = host.connect(await getSigner(1));
  });

  async function revertData(call: Promise<unknown>): Promise<string> {
    try {
      await call;
    } catch (e: any) {
      return e.data ?? e.info?.error?.data;
    }
    throw new Error("expected a revert");
  }
  const errors = new ethers.Interface(["error Untrusted(bytes32 id)", "error InvalidBlock()"]);
  const untrusted = (id: bigint) => errors.encodeErrorResult("Untrusted", [ethers.toBeHex(id, 32)]);

  it("publishes the endorsement ports with ENTITY input and the Input hint", async () => {
    for (const method of ["portEndorse", "portUnendorse"]) {
      const id = await portId(`${method}(bytes)`, host);
      await expect(host.deploymentTransaction()).to.emitEndpoint(host)
        .withArgs(id, ...endpointSpecs({ input: Keys.Entity, inputHint: 32 }));
    }
  });

  it("lets trusted peers endorse and unendorse non-node IDs with Trust records", async () => {
    const input = concat(encodeEntityBlock(asset), encodeEntityBlock(other));
    await expectTrustLogs(peer.portEndorse(input), [asset, other], true);
    expect([await host.isTrusted(asset), await host.isTrusted(other)]).deep.eq([true, true]);
    await expectTrustLogs(peer.portEndorse(input), [], true);
    await expectTrustLogs(peer.portUnendorse(encodeEntityBlock(asset)), [asset], false);
    expect(await host.isTrusted(asset)).eq(false);
    expect(Array.from(await peer.portEndorse.staticCall("0x"))).deep.eq(["0x", 0n]);
  });

  it("rejects node IDs and untrusted callers on the endorsement ports", async () => {
    const node = await hostId(await (await getSigner(3)).getAddress());
    for (const method of ["portEndorse", "portUnendorse"]) {
      await expect(peer[method](encodeEntityBlock(node))).to.be.revertedWithCustomError(host, "AccessDenied");
    }
    const stranger = host.connect(await getSigner(2));
    await expect(stranger.portEndorse(encodeEntityBlock(asset))).to.be.revertedWithCustomError(host, "AccessDenied");
    await expect(peer.portEndorse(encodeEntityBlock(0n))).to.be.revertedWithCustomError(host, "InvalidId");
  });

  it("checks raw packed IDs and reverts Untrusted for the first miss", async () => {
    await peer.portEndorse(encodeEntityBlock(asset));
    const call = (...ids: bigint[]) => host.runner.call({ to: host.target, data: concat(CHECK_TRUST, ...ids.map((id) => ethers.toBeHex(id, 32))) });
    expect(await call(asset)).eq("0x");
    expect(await call()).eq("0x");
    expect(await revertData(call(asset, other))).eq(untrusted(other));
    expect(await revertData(host.runner.call({ to: host.target, data: concat(CHECK_TRUST, "0x01") })))
      .eq(errors.encodeErrorResult("InvalidBlock", []));
  });

  it("requires trust through Runtime with one ID or packed memory IDs", async () => {
    await peer.portEndorse(encodeEntityBlock(asset));
    await host.requireOne(ethers.toBeHex(asset, 32));
    expect(await revertData(host.requireOne(ethers.toBeHex(other, 32)))).eq(untrusted(other));
    await host.requireMany([ethers.toBeHex(asset, 32), ethers.toBeHex(asset, 32)]);
    await host.requireMany([]);
    expect(await revertData(host.requireMany([ethers.toBeHex(asset, 32), ethers.toBeHex(other, 32)]))).eq(untrusted(other));
  });

  it("always trusts the chain and Rootzero assets without registry entries, and refuses to record them", async () => {
    const chain = BigInt(await (await deploy("TestUtils")).testToChain());
    const rootzero = 0x0103n << 240n;
    for (const native of [chain, rootzero]) {
      expect(await host.isTrusted(native)).eq(false);
      await host.requireOne(ethers.toBeHex(native, 32));
      await host.requireMany([ethers.toBeHex(native, 32), ethers.toBeHex(native, 32)]);
      expect(await host.runner.call({ to: host.target, data: concat(CHECK_TRUST, ethers.toBeHex(native, 32)) })).eq("0x");
      await expect(peer.portEndorse(encodeEntityBlock(native))).to.be.revertedWithCustomError(host, "InvalidId");
      await expect(peer.portUnendorse(encodeEntityBlock(native))).to.be.revertedWithCustomError(host, "InvalidId");
    }
  });
});
