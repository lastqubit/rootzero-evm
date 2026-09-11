import { expect } from "chai";
import { ethers } from "ethers";
import { deploy, getProvider, getSigner, hostId, portId } from "./helpers/setup.js";
import {
  encodeDispatchBlock,
  encodeContextBlock,
  encodeNodeBlock,
  encodeRecoverBlock,
} from "./helpers/blocks.js";
import "./helpers/matchers.js";

describe("Portal", () => {
  async function commandCtx(host: any, input: string) {
    return [encodeContextBlock(await host.getAdminAccount(), "0x", input)] as const;
  }

  async function authorize(host: any, node: bigint) {
    return host.authorize(...await commandCtx(host, encodeNodeBlock(node)));
  }

  async function deployPortal() {
    const commander = await deployPortHost();
    const portal = await deploy("TestPortalRecoverHost", await hostId(commander));
    return { portal, commander };
  }

  async function deployPortHost() {
    const commander = await (await getSigner(0)).getAddress();
    return deploy("TestPortHost", await hostId(commander));
  }

  async function dispatchPort(host: Awaited<ReturnType<typeof deploy>>) {
    return portId(host.interface.getFunction("portDispatchPayable(bytes)")!.selector, host);
  }

  async function callPortal(
    commander: Awaited<ReturnType<typeof deploy>>,
    portal: Awaited<ReturnType<typeof deploy>>,
    method: string,
    args: readonly unknown[],
    value = 0n,
  ) {
    const data = portal.interface.encodeFunctionData(method, args);
    return commander.testCall(await portal.getAddress(), data, { value });
  }

  async function authorizePortal(
    commander: Awaited<ReturnType<typeof deploy>>,
    portal: Awaited<ReturnType<typeof deploy>>,
    node: bigint,
  ) {
    return callPortal(
      commander,
      portal,
      "authorize",
      await commandCtx(portal, encodeNodeBlock(node)),
    );
  }

  async function recoverPortal(
    commander: Awaited<ReturnType<typeof deploy>>,
    portal: Awaited<ReturnType<typeof deploy>>,
    input: string,
    value = 0n,
  ) {
    return callPortal(
      commander,
      portal,
      "recoverPayable",
      await commandCtx(portal, input),
      value,
    );
  }

  it("forwards contexts to the commander's payable pipeline without recording unresolved state", async () => {
    const { portal, commander } = await deployPortal();

    await authorize(commander, await portal.host());

    const key = ethers.zeroPadValue("0x01", 32);
    const message = encodeContextBlock(await portal.getAdminAccount(), "0x", "0x");
    const provider = await getProvider();
    const commanderAddr = await commander.getAddress();
    const before = BigInt(await provider.send("eth_getBalance", [commanderAddr, "latest"]));

    // Estimation may select the cheaper direct-storage path; budget for delivery.
    const tx = await portal.testForward(key, message, 7n, { value: 7n, gasLimit: 500_000 });
    await expect(tx).to.emit(commander, "CashinCalled").withArgs(await portal.getAdminAccount(), 7n);
    const receipt = await tx.wait();
    expect(receipt!.logs).to.have.length(1);

    const after = BigInt(await provider.send("eth_getBalance", [commanderAddr, "latest"]));
    expect(after).to.equal(before + 7n);

    const input = encodeRecoverBlock(await dispatchPort(commander), 0n, key, message);
    await expect(recoverPortal(commander, portal, input))
      .to.be.revertedWithCustomError(portal, "BadWitness");
  });

  it("calls ports from memory input", async () => {
    const target = await deployPortHost();
    const handler = await dispatchPort(target);
    const { portal, commander } = await deployPortal();

    await authorizePortal(commander, portal, handler);
    await authorize(target, await portal.host());

    const message = encodeDispatchBlock(0n, 2n, "0x1234");
    const result = await portal.testCallPortMemory.staticCall(handler, message, 0n);

    expect(result).to.deep.equal(["0x", 0n]);
  });

  it("records unresolved messages when forwarding fails", async () => {
    const { portal } = await deployPortal();

    const key = ethers.zeroPadValue("0x02", 32);
    const message = encodeContextBlock(await portal.getAdminAccount(), "0x", "0x");
    const digest = ethers.keccak256(message);

    const tx = await portal.testForward(key, message, 0n);

    await expect(tx).to.emit(portal, "Unresolved").withArgs(await portal.host(), key, digest);
  });

  it("recovers a matching witness through the supplied handler and resolves the key", async () => {
    const recoveryTarget = await deployPortHost();
    const recoveryHandler = await dispatchPort(recoveryTarget);
    const { portal, commander } = await deployPortal();

    await authorizePortal(commander, portal, recoveryHandler);
    await authorize(recoveryTarget, await portal.host());

    const key = ethers.zeroPadValue("0x03", 32);
    const witness = encodeDispatchBlock(0n, 9n, "0xcafe");
    await portal.testForward(key, witness, 0n);

    const input = encodeRecoverBlock(recoveryHandler, 5n, key, witness);
    const callData = portal.interface.encodeFunctionData(
      "recoverPayable", await commandCtx(portal, input),
    );
    const returned = await commander.testCall.staticCall(await portal.getAddress(), callData, { value: 5n });
    expect(portal.interface.decodeFunctionResult("recoverPayable", returned))
      .to.deep.equal(["0x", 5n]);
    const tx = await recoverPortal(commander, portal, input, 5n);

    await expect(tx).to.emit(recoveryTarget, "PortDispatchCalled").withArgs(0n, "0xcafe", 9n, 5n);
    await expect(tx).to.emit(portal, "Resolved").withArgs(await portal.host(), key);

    const second = encodeRecoverBlock(recoveryHandler, 0n, key, witness);
    await expect(recoverPortal(commander, portal, second))
      .to.be.revertedWithCustomError(portal, "BadWitness");
  });

  it("settles pipeline recovery value to its context without also returning it as credit", async () => {
    const target = await deployPortHost();
    const handler = await portId("portPipePayable(bytes)", target);
    const { portal, commander } = await deployPortal();
    await authorizePortal(commander, portal, handler);
    await authorize(target, await portal.host());

    const key = ethers.zeroPadValue("0x06", 32);
    // The recovered subject differs from the account paying for recovery.
    const witness = encodeContextBlock(ethers.zeroPadValue("0xab", 32), "0x", "0x");
    await portal.testForward(key, witness, 0n);
    const input = encodeRecoverBlock(handler, 5n, key, witness);
    const data = portal.interface.encodeFunctionData("recoverPayable", await commandCtx(portal, input));
    // Two wei stay in the command budget; the port settles the other five.
    const returned = await commander.testCall.staticCall(await portal.getAddress(), data, { value: 7n });
    expect(portal.interface.decodeFunctionResult("recoverPayable", returned))
      .to.deep.equal(["0x", 2n]);
    const tx = await recoverPortal(commander, portal, input, 7n);
    await expect(tx).to.emit(target, "CashinCalled").withArgs(ethers.zeroPadValue("0xab", 32), 5n);
    await expect(tx)
      .to.emit(portal, "Resolved").withArgs(await portal.host(), key);
  });

  it("restores the unresolved witness when the recovery handler fails", async () => {
    const recoveryTarget = await deployPortHost();
    const recoveryHandler = await dispatchPort(recoveryTarget);
    const { portal, commander } = await deployPortal();

    await authorizePortal(commander, portal, recoveryHandler);

    const key = ethers.zeroPadValue("0x05", 32);
    const witness = encodeDispatchBlock(0n, 4n, "0xdead");
    await portal.testForward(key, witness, 0n);

    const input = encodeRecoverBlock(recoveryHandler, 0n, key, witness);
    let failure: string | undefined;
    try {
      await recoverPortal(commander, portal, input);
    } catch (error: any) {
      failure = error.data ?? error.info?.error?.data;
    }
    expect(failure?.slice(0, 10)).to.equal("0x20577b07");

    const authorization = await authorize(recoveryTarget, await portal.host());
    await authorization.wait();
    const retryData = portal.interface.encodeFunctionData(
      "recoverPayable",
      await commandCtx(portal, input),
    );
    const retry = await commander.testCall(
      await portal.getAddress(),
      retryData,
      { gasLimit: 5_000_000n },
    );
    await expect(retry).to.emit(recoveryTarget, "PortDispatchCalled")
      .withArgs(0n, "0xdead", 4n, 0n);
  });

  it("rejects recovery when the witness does not match the recorded digest", async () => {
    const recoveryTarget = await deployPortHost();
    const recoveryHandler = await dispatchPort(recoveryTarget);
    const { portal, commander } = await deployPortal();

    await authorizePortal(commander, portal, recoveryHandler);
    await authorize(recoveryTarget, await portal.host());

    const key = ethers.zeroPadValue("0x04", 32);
    const witness = encodeDispatchBlock(0n, 1n, "0xaaaa");
    const badWitness = encodeDispatchBlock(0n, 1n, "0xbbbb");
    await portal.testForward(key, witness, 0n);

    const input = encodeRecoverBlock(recoveryHandler, 0n, key, badWitness);
    await expect(recoverPortal(commander, portal, input))
      .to.be.revertedWithCustomError(portal, "BadWitness");
  });
});
