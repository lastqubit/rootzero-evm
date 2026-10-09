import { expect } from "chai";
import { ethers } from "ethers";
import { deploy, getSigner, hostId } from "./helpers/setup.js";
import { encodeHostAccount, encodeNodeBlock, encodeStepBlock } from "./helpers/blocks.js";
import { decodeEndpointLog } from "./helpers/endpoint-logs.js";
import { decodeIntroductionLog } from "./helpers/introduction-logs.js";

describe("Runtime execution identity", () => {
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
    await host.testPipe(admin, encodeStepBlock(command, 0n, encodeNodeBlock(node)));
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
    await upgraded.testPipe(admin, encodeStepBlock(command, 0n, encodeNodeBlock(await hostId(self))));
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
