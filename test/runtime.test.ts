import { expect } from "chai";
import { ethers } from "ethers";
import { deploy, getSigner, hostId } from "./helpers/setup.js";
import { encodeHostAccount, encodeEntityBlock, encodeStepBlock } from "./helpers/blocks.js";
import { decodeEndpointLog } from "./helpers/endpoint-logs.js";
import { decodeIntroductionLog } from "./helpers/introduction-logs.js";

describe("Runtime execution identity", () => {
  describe("remote commander policy", () => {
    let commander: Awaited<ReturnType<typeof deploy>>;

    beforeEach(async () => {
      const root = await deploy("TestRuntime", 0, ethers.ZeroAddress);
      commander = await deploy("TestRemoteCommander", await root.host(), ethers.ZeroAddress);
    });

    it("accepts a deployed commander for ordinary and proxy-bound hosts", async () => {
      const proxy = await deploy("TestRuntimeProxy");
      for (const self of [ethers.ZeroAddress, await proxy.getAddress()]) {
        const host = await deploy("TestRemoteCommander", await commander.host(), self);
        expect(await host.remoteCommander()).eq(await commander.getAddress());
        if (self !== ethers.ZeroAddress) {
          await proxy.upgrade(await host.getAddress());
          expect(await host.attach(self).remoteCommander()).eq(await commander.getAddress());
        }
      }
    });

    it("rejects implicit and explicit self-management, including the proxy execution address", async () => {
      await expect(deploy("TestRemoteCommander", 0, ethers.ZeroAddress))
        .to.be.revertedWithCustomError(commander, "InvalidCommander");
      const signer = await getSigner();
      const predicted = ethers.getCreateAddress({ from: await signer.getAddress(), nonce: await signer.getNonce() });
      await expect(deploy("TestRemoteCommander", await hostId(predicted), ethers.ZeroAddress))
        .to.be.revertedWithCustomError(commander, "InvalidCommander");
      const proxy = await deploy("TestRuntimeProxy");
      for (const cmdr of [0n, await hostId(proxy)]) {
        await expect(deploy("TestRemoteCommander", cmdr, await proxy.getAddress()))
          .to.be.revertedWithCustomError(commander, "InvalidCommander");
      }
    });

    it("rejects commanders without deployed bytecode", async () => {
      for (const target of [await (await getSigner(1)).getAddress(), ethers.toBeHex(0x1234, 20)]) {
        await expect(deploy("TestRemoteCommander", await hostId(target), ethers.ZeroAddress))
          .to.be.revertedWithCustomError(commander, "InvalidContract");
      }
    });

    it("requires a canonical local host ID", async () => {
      const cmdr = BigInt(await commander.host());
      for (const invalid of [
        cmdr ^ (1n << 192n), // Foreign chain.
        cmdr | (1n << 160n), // Nonzero selector.
        cmdr | (1n << 224n), // Host flags.
        cmdr ^ (1n << 232n), // Different node subtype.
      ]) {
        await expect(deploy("TestRemoteCommander", invalid, ethers.ZeroAddress))
          .to.be.revertedWithCustomError(commander, "InvalidId");
      }
    });
  });

  for (const explicit of [false, true]) {
    it(`binds inherited identities to ${explicit ? "an explicit execution address" : "the deployment address"}`, async () => {
      const self = explicit ? await (await getSigner(1)).getAddress() : ethers.ZeroAddress;
      const host = await deploy("TestRuntime", 0, self);
      const expected = explicit ? self : await host.getAddress();
      expect(await host.hostAddr()).eq(expected);
      expect(await host.host()).eq(await hostId(expected));
      expect(await host.hostAccount()).eq(encodeHostAccount(await hostId(expected)));
      expect(await host.adminAccount()).eq(ethers.toBeHex(
        (0x03010100n << 224n) | ((await hostId(expected)) & ((1n << 224n) - 1n)), 32));

      const receipt = await host.deploymentTransaction().wait();
      const endpoints = receipt.logs.map(decodeEndpointLog).filter(
        (entry: ReturnType<typeof decodeEndpointLog>) => entry !== null);
      const names = endpoints.map((entry: NonNullable<ReturnType<typeof decodeEndpointLog>>) => entry[4]);
      for (const name of ["authorize", "portCreditAccount", "getBalance", "revoke"]) {
        expect(names).include(name);
      }
      for (const entry of endpoints) {
        expect(ethers.getAddress(ethers.toBeHex(entry[0] & ((1n << 160n) - 1n), 20))).eq(expected);
      }
    });
  }

  it("dispatches locally through a proxy and retains authorization when adding a command", async () => {
    const proxy = await deploy("TestRuntimeProxy");
    const self = await proxy.getAddress();
    const implementation = await deploy("TestRuntime", 0, self);
    await proxy.upgrade(await implementation.getAddress());
    const host = implementation.attach(self);
    const admin = await host.adminAccount();
    const command = await host.commandId();
    const node = await hostId(await (await getSigner(2)).getAddress());
    expect(await host.hostAddr()).eq(self);
    expect(await host.isAuthorized(command)).eq(false);
    await host.testPipe(admin, encodeStepBlock(command, 0n, encodeEntityBlock(node)));
    expect(await host.isAuthorized(node)).eq(true);
    expect(await implementation.isAuthorized(node)).eq(false);

    const next = await deploy("TestRuntimeV2", self);
    await proxy.upgrade(await next.getAddress());
    const upgraded = next.attach(self);
    expect(await upgraded.commandId()).eq(command);
    expect(await upgraded.adminAccount()).eq(admin);
    expect(await upgraded.isAuthorized(node)).eq(true);
    const steps = encodeStepBlock(await upgraded.markId(), 3n, "0x");
    expect(await upgraded.testPipe.staticCall(admin, steps, { value: 3n })).eq(3n);
    await upgraded.testPipe(admin, steps, { value: 3n });
    expect(await upgraded.markers()).eq(1n);
    expect(await next.markers()).eq(0n);
    await upgraded.testPipe(admin, encodeStepBlock(command, 0n, encodeEntityBlock(await hostId(self))));
    expect(await upgraded.isAuthorized(await hostId(self))).eq(true);
  });

  it("defers a bound implementation's introduction until it runs through its execution address", async () => {
    const commander = await deploy("TestRuntime", 0, ethers.ZeroAddress);
    const proxy = await deploy("TestRuntimeProxy");
    const implementation = await deploy("TestRuntime", await commander.host(), await proxy.getAddress());
    const receipt = await implementation.deploymentTransaction().wait();
    expect(receipt.logs.map(decodeIntroductionLog).filter(Boolean)).deep.eq([]);
    await proxy.upgrade(await implementation.getAddress());
    const host = implementation.attach(await proxy.getAddress());
    const introduced = await (await host.announce(await commander.host())).wait();
    const records = introduced.logs.map(decodeIntroductionLog).filter(Boolean);
    expect(records).length(1);
    expect(records[0].peer).eq(await host.host());
  });
});
