import { expect } from "chai";
import { ethers } from "ethers";
import hre from "hardhat";
import "./helpers/matchers.js";
import { commandId, deploy, getSigner, getSigners, hostId, portId } from "./helpers/setup.js";
import { encodeContextBlock, encodeNodeBlock, pad32 } from "./helpers/blocks.js";

describe("Access Control", () => {
  let host: Awaited<ReturnType<typeof deploy>>;
  let utils: Awaited<ReturnType<typeof deploy>>;
  let commander: string;
  let stranger: string;
  let hostAddress: string;

  before(async () => {
    const signers = await getSigners(3);
    commander = await signers[0].getAddress();
    stranger  = await signers[1].getAddress();

    host = await deploy("TestHost", await hostId(commander));
    utils = await deploy("TestUtils");
    hostAddress = await host.getAddress();
  });

  async function localNode(signerIndex: number) {
    return utils.testToHostId(await (await getSigner(signerIndex)).getAddress());
  }

  it("host ID is derived from contract address", async () => {
    const hostId: bigint = await host.host();
    // Lower 160 bits should be the contract address
    const embedded = hostId & ((1n << 160n) - 1n);
    expect("0x" + embedded.toString(16).padStart(40, "0"))
      .to.equal(hostAddress.toLowerCase());
  });

  it("adminAccount encodes the commander host's native identity", async () => {
    const adminAccount: string = await host.getAdminAccount();
    const val = BigInt(adminAccount);
    const embedded = val & ((1n << 160n) - 1n);
    expect("0x" + embedded.toString(16).padStart(40, "0"))
      .to.equal(commander.toLowerCase());
  });

  it("retains the commander host ID and its resolved native address", async () => {
    expect(await host.getCommander()).to.equal(await hostId(commander));
    expect(await host.getCommanderAddr()).to.equal(commander);
  });

  it("commander is trusted", async () => {
    // Commander can call trusted-only functions without reverting.
    // An empty authorize batch is a successful no-op.
    const adminAccount: string = await host.getAdminAccount();
    const ctx = [encodeContextBlock(adminAccount, "0x", "0x")] as const;
    const signers = await getSigners(1);
    await host.connect(signers[0]).authorize(...ctx);
  });

  it("stranger is not trusted and gets AccessDenied", async () => {
    const adminAccount: string = await host.getAdminAccount();
    const ctx = [encodeContextBlock(adminAccount, "0x", "0x")] as const;
    const signers = await getSigners(2);
    await expect(
      host.connect(signers[1]).authorize(...ctx)
    ).to.be.revertedWithCustomError(host, "AccessDenied");
  });

  it("enforces the expected message sender", async () => {
    const signers = await getSigners(2);

    expect(await utils.connect(signers[0]).testEnforceSender(commander))
      .to.equal(commander);
    await expect(utils.connect(signers[1]).testEnforceSender(commander))
      .to.be.revertedWithCustomError(utils, "AccessDenied");
  });

  it("authorize emits Node event with active=true", async () => {
    const signers = await getSigners(1);
    const adminAccount: string = await host.getAdminAccount();
    const dummyNode = await localNode(3);
    const nodeBlock = encodeNodeBlock(dummyNode);
    const ctx = [encodeContextBlock(adminAccount, "0x", nodeBlock)] as const;

    await expect(host.connect(signers[0]).authorize(...ctx))
      .to.emit(host, "Node")
      .withArgs(await host.host(), dummyNode, 16n, 1n);
  });

  it("node is authorized after authorize call", async () => {
    const signers = await getSigners(1);
    const adminAccount: string = await host.getAdminAccount();
    const dummyNode = await localNode(4);
    const nodeBlock = encodeNodeBlock(dummyNode);
    const ctx = [encodeContextBlock(adminAccount, "0x", nodeBlock)] as const;
    await host.connect(signers[0]).authorize(...ctx);
    expect(await host.isAuthorized(dummyNode)).to.be.true;
  });

  it("unauthorize emits Node event with active=false", async () => {
    const signers = await getSigners(1);
    const adminAccount: string = await host.getAdminAccount();
    const dummyNode = await localNode(5);
    // First authorize
    await host.connect(signers[0]).authorize(encodeContextBlock(adminAccount, "0x", encodeNodeBlock(dummyNode)));
    // Then unauthorize
    await expect(
      host.connect(signers[0]).unauthorize(encodeContextBlock(adminAccount, "0x", encodeNodeBlock(dummyNode)))
    ).to.emit(host, "Node").withArgs(await host.host(), dummyNode, 17n, 0n);
  });

  it("node is not authorized after unauthorize call", async () => {
    const signers = await getSigners(1);
    const adminAccount: string = await host.getAdminAccount();
    const dummyNode = await localNode(6);
    await host.connect(signers[0]).authorize(encodeContextBlock(adminAccount, "0x", encodeNodeBlock(dummyNode)));
    await host.connect(signers[0]).unauthorize(encodeContextBlock(adminAccount, "0x", encodeNodeBlock(dummyNode)));
    expect(await host.isAuthorized(dummyNode)).to.be.false;
  });

  it("isAuthorized mapping returns false for node 0", async () => {
    expect(await host.isAuthorized(0n)).to.be.false;
  });

  it("enforces endpoint type and trust together for commands and ports", async () => {
    const command = await commandId("trusted(bytes)", host);
    const port = await portId("trusted(bytes)", host);
    const adminAccount: string = await host.getAdminAccount();
    const signers = await getSigners(1);

    for (const node of [command, port]) {
      await host.connect(signers[0]).authorize(
        encodeContextBlock(adminAccount, "0x", encodeNodeBlock(node)),
      );
    }

    const commandEndpoint = await host.testEnforceCommand(command);
    expect(commandEndpoint[0]).to.equal(ethers.id("trusted(bytes)").slice(0, 10));
    expect(commandEndpoint[1]).to.equal(hostAddress);
    const portEndpoint = await host.testEnforcePort(port);
    expect(portEndpoint[0]).to.equal(ethers.id("trusted(bytes)").slice(0, 10));
    expect(portEndpoint[1]).to.equal(hostAddress);
    const trustedEndpoint = await host.testEnforceNode(command);
    expect(trustedEndpoint[0]).to.equal(commandEndpoint[0]);
    expect(trustedEndpoint[1]).to.equal(commandEndpoint[1]);
    await expect(host.testEnforceCommand(port))
      .to.be.revertedWithCustomError(host, "InvalidId");
    await expect(host.testEnforcePort(command))
      .to.be.revertedWithCustomError(host, "InvalidId");

    const untrustedCommand = await commandId("untrusted(bytes)", host);
    const untrustedPort = await portId("untrusted(bytes)", host);
    await expect(host.testEnforceCommand(untrustedCommand))
      .to.be.revertedWithCustomError(host, "AccessDenied");
    await expect(host.testEnforcePort(untrustedPort))
      .to.be.revertedWithCustomError(host, "AccessDenied");
    await expect(host.testEnforceNode(untrustedPort))
      .to.be.revertedWithCustomError(host, "AccessDenied");
  });

  it("isGuardian converts an address to its user account", async () => {
    const guardianAddress = await (await getSigner(2)).getAddress();
    const guardianAccount = await utils.testToUserAccount(guardianAddress);

    expect(await host.isGuardianAddress(guardianAddress)).to.be.false;

    await host.appointGuardianAccount(guardianAccount);
    expect(await host.isGuardianAddress(guardianAddress)).to.be.true;
  });

  it("falls back to the host address when commander is zero", async () => {
    const selfManaged = await deploy("TestHost", 0n);
    const selfManagedAddress = await selfManaged.getAddress();
    expect(await selfManaged.getCommander()).to.equal(await selfManaged.host());
    expect(await selfManaged.getCommanderAddr()).to.equal(selfManagedAddress);

    const adminAccount: string = await selfManaged.getAdminAccount();
    const val = BigInt(adminAccount);
    const embedded = val & ((1n << 160n) - 1n);
    expect("0x" + embedded.toString(16).padStart(40, "0"))
      .to.equal(selfManagedAddress.toLowerCase());
  });

  it("rejects non-host and foreign-chain commander IDs", async () => {
    const local = await hostId(commander);
    const nonHost = local ^ (1n << 224n);
    const foreign = local ^ (1n << 192n);

    for (const commanderId of [nonHost, foreign]) {
      let rejected = false;
      try {
        await deploy("TestHost", commanderId);
      } catch {
        rejected = true;
      }
      expect(rejected).to.equal(true);
    }
  });
});

describe("Commander Access", () => {
  it("rejects a zero commander", async () => {
    let rejected = false;
    try {
      await deploy("TestMinimalCommandHost", 0n);
    } catch {
      rejected = true;
    }
    expect(rejected).to.equal(true);
  });

  it("allows the commander to call a command", async () => {
    const signers = await getSigners(1);
    const commander = await signers[0].getAddress();
    const host = await deploy("TestMinimalCommandHost", await hostId(commander));

    expect(await host.connect(signers[0]).ping()).to.equal(true);
  });

  it("rejects other command callers", async () => {
    const signers = await getSigners(2);
    const commander = await signers[0].getAddress();
    const host = await deploy("TestMinimalCommandHost", await hostId(commander));

    await expect(host.connect(signers[1]).ping())
      .to.be.revertedWithCustomError(host, "AccessDenied");
  });

  it("does not expose advanced host entrypoints or accept direct native transfers", async () => {
    const signers = await getSigners(1);
    const host = await deploy("TestMinimalCommandHost", await hostId(await signers[0].getAddress()));

    for (const name of [
      "annotate",
      "authorize",
      "unauthorize",
      "appoint",
      "dismiss",
      "executePayable",
      "revoke",
      "introduce",
    ]) {
      expect(host.interface.getFunction(name)).to.equal(null);
    }

    let rejected = false;
    try {
      const tx = await signers[0].sendTransaction({ to: await host.getAddress(), value: 1n });
      await tx.wait();
    } catch {
      rejected = true;
    }
    expect(rejected).to.equal(true);
  });

  it("stays materially smaller than the built-in advanced host", async () => {
    const minimal = await hre.artifacts.readArtifact("TestMinimalCommandHost");
    const advanced = await hre.artifacts.readArtifact("TestBareHost");
    const minimalSize = ethers.getBytes(minimal.deployedBytecode).length;
    const advancedSize = ethers.getBytes(advanced.deployedBytecode).length;

    expect(minimalSize).to.be.lessThan(advancedSize / 2);
  });
});
