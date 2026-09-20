import { expect } from "chai";
import { ethers } from "ethers";
import hre from "hardhat";
import "./helpers/matchers.js";
import { commandId, deploy, getSigner, guardId, hostId } from "./helpers/setup.js";
import {
  encodeAccountBlock,
  encodeAssetBlock,
  encodeContextBlock,
  encodeHostAssetBlock,
  encodeLabelBlock,
  encodeNodeBlock,
  endpointDescriptor,
  Keys,
  pad32,
} from "./helpers/blocks.js";

describe("Guard Actions", () => {
  let host: Awaited<ReturnType<typeof deploy>>;
  let utils: Awaited<ReturnType<typeof deploy>>;
  let adminAccount: string;
  let commander: string;
  let guardianAddress: string;
  let guardianSigner: Awaited<ReturnType<typeof getSigner>>;

  beforeEach(async () => {
    commander = await (await getSigner(0)).getAddress();
    guardianSigner = await getSigner(1);
    guardianAddress = await guardianSigner.getAddress();

    host = await deploy("TestHost", await hostId(commander));
    utils = await deploy("TestUtils");
    adminAccount = await host.getAdminAccount();

    const guardianAccount = await utils.testToUserAccount(guardianAddress);
    await host.appoint(...adminCtx(encodeAccountBlock(guardianAccount)));
  });

  function adminCtx(input: string) {
    return [encodeContextBlock(adminAccount, "0x", input)] as const;
  }

  async function cmd(method: string) {
    const flags = ["appoint", "dismiss", "authorize", "unauthorize", "annotate"].includes(method) ? 2n : 0n;
    return commandId(host.interface.getFunction(method)!.selector, host, flags);
  }

  async function guard(method: string, target = host) {
    return guardId(target.interface.getFunction(method)!.selector, target);
  }

  it("emits Endpoint discovery for revoke on deployment", async () => {
    const signer = await getSigner(0);
    const artifact = await hre.artifacts.readArtifact("TestHost");
    const factory = new ethers.ContractFactory(artifact.abi, artifact.bytecode, signer);
    const deployed = await factory.deploy(await hostId(commander));
    const deploymentTx = deployed.deploymentTransaction();
    if (!deploymentTx) throw new Error("missing deployment transaction");
    await deployed.waitForDeployment();

    await expect(deploymentTx)
      .to.emit(deployed, "Endpoint")
      .withArgs(await (deployed as any).host(), await guard("revoke", deployed), endpointDescriptor({ input: Keys.Node, inputHint: 32 }));
    await expect(deploymentTx)
      .to.emit(deployed, "Annotation")
      .withArgs(await guard("revoke", deployed), encodeLabelBlock(ethers.ZeroHash, "revoke"));
    await expect(deploymentTx)
      .to.emit(deployed, "Endpoint")
      .withArgs(
        await (deployed as any).host(),
        await guard("revokeAllowance", deployed),
        endpointDescriptor({ input: Keys.HostAsset, inputHint: 64 }),
      );
    await expect(deploymentTx)
      .to.emit(deployed, "Annotation")
      .withArgs(
        await guard("revokeAllowance", deployed),
        encodeLabelBlock(ethers.ZeroHash, "revokeAllowance"),
      );
    await expect(deploymentTx)
      .to.emit(deployed, "Endpoint")
      .withArgs(
        await (deployed as any).host(),
        await guard("revokeAsset", deployed),
        endpointDescriptor({ input: Keys.Asset, inputHint: 32 }),
      );
    await expect(deploymentTx)
      .to.emit(deployed, "Annotation")
      .withArgs(
        await guard("revokeAsset", deployed),
        encodeLabelBlock(ethers.ZeroHash, "revokeAsset"),
      );
  });

  it("guardian can revoke assets", async () => {
    const asset1 = ethers.id("asset-1");
    const asset2 = ethers.id("asset-2");

    const tx = host.connect(guardianSigner).revokeAsset(ethers.concat([
      encodeAssetBlock(asset1),
      encodeAssetBlock(asset2),
    ]));
    await expect(tx).to.emit(host, "DenyAssetCalled").withArgs(asset1);
    await expect(tx).to.emit(host, "DenyAssetCalled").withArgs(asset2);
  });

  it("non-guardians cannot revoke assets", async () => {
    await expect(host.revokeAsset(encodeAssetBlock(ethers.id("asset"))))
      .to.be.revertedWithCustomError(host, "AccessDenied");
  });

  it("revokeAsset accepts an empty batch", async () => {
    await host.connect(guardianSigner).revokeAsset("0x");
  });

  it("guardian can revoke host asset allowances", async () => {
    const peer1 = await hostId(await (await getSigner(2)).getAddress());
    const peer2 = await hostId(await (await getSigner(3)).getAddress());
    const asset1 = ethers.id("asset-1");
    const asset2 = ethers.id("asset-2");

    const tx = host.connect(guardianSigner).revokeAllowance(ethers.concat([
      encodeHostAssetBlock(peer1, asset1),
      encodeHostAssetBlock(peer2, asset2),
    ]));
    await expect(tx).to.emit(host, "AllowanceCalled").withArgs(peer1, asset1, 0n);
    await expect(tx).to.emit(host, "AllowanceCalled").withArgs(peer2, asset2, 0n);
  });

  it("non-guardians cannot revoke allowances", async () => {
    await expect(host.revokeAllowance(encodeHostAssetBlock(1n, ethers.id("asset"))))
      .to.be.revertedWithCustomError(host, "AccessDenied");
  });

  it("revokeAllowance accepts an empty batch", async () => {
    await host.connect(guardianSigner).revokeAllowance("0x");
  });

  it("revokeAllowance rejects allowance blocks carrying an amount", async () => {
    const allowance = ethers.concat([
      Keys.Allowance,
      ethers.toBeHex(96, 4),
      pad32(1n),
      pad32(ethers.id("asset")),
      pad32(10n),
    ]);

    await expect(host.connect(guardianSigner).revokeAllowance(allowance))
      .to.be.revertedWithCustomError(host, "InvalidBlock");
  });

  it("guardian can revoke an authorized node directly", async () => {
    const node = await hostId(await (await getSigner(2)).getAddress());

    await host.authorize(...adminCtx(encodeNodeBlock(node)));
    expect(await host.isAuthorized(node)).to.be.true;

    await expect(host.connect(guardianSigner).revoke(encodeNodeBlock(node)))
      .to.emit(host, "Node")
      .withArgs(await host.host(), node, 17n, 0n);

    expect(await host.isAuthorized(node)).to.be.false;
  });

  it("guardian can revoke multiple nodes", async () => {
    const node1 = await hostId(await (await getSigner(2)).getAddress());
    const node2 = await hostId(await (await getSigner(3)).getAddress());

    await host.authorize(...adminCtx(ethers.concat([encodeNodeBlock(node1), encodeNodeBlock(node2)])));

    await host.connect(guardianSigner).revoke(ethers.concat([encodeNodeBlock(node1), encodeNodeBlock(node2)]));

    expect(await host.isAuthorized(node1)).to.be.false;
    expect(await host.isAuthorized(node2)).to.be.false;
  });

  it("reverts AccessDenied for non-guardian callers", async () => {
    const node = await hostId(await (await getSigner(2)).getAddress());

    await expect(host.revoke(encodeNodeBlock(node)))
      .to.be.revertedWithCustomError(host, "AccessDenied");
  });

  it("accepts an empty revoke batch", async () => {
    await host.connect(guardianSigner).revoke("0x");
  });

  it("reverts InvalidBlock when revoke input is not NODE blocks", async () => {
    const guardianAccount = await utils.testToUserAccount(guardianAddress);

    await expect(host.connect(guardianSigner).revoke(encodeAccountBlock(guardianAccount)))
      .to.be.revertedWithCustomError(host, "InvalidBlock");
  });

  it("reverts OutOfBounds when revoke input has a truncated NODE block", async () => {
    const truncated = ethers.concat([
      Keys.Node,
      ethers.toBeHex(32, 4),
      ethers.dataSlice(pad32(1n), 0, 31),
    ]);

    await expect(host.connect(guardianSigner).revoke(truncated))
      .to.be.revertedWithCustomError(host, "OutOfBounds");
  });

  it("dismissed guardian cannot revoke nodes", async () => {
    const node = await hostId(await (await getSigner(2)).getAddress());
    await host.authorize(...adminCtx(encodeNodeBlock(node)));

    const guardianAccount = await utils.testToUserAccount(guardianAddress);
    await host.dismiss(...adminCtx(encodeAccountBlock(guardianAccount)));

    await expect(host.connect(guardianSigner).revoke(encodeNodeBlock(node)))
      .to.be.revertedWithCustomError(host, "AccessDenied");
  });

  it("appointing the same guardian twice is idempotent", async () => {
    const guardianAccount = await utils.testToUserAccount(guardianAddress);

    await expect(host.appoint(...adminCtx(encodeAccountBlock(guardianAccount))))
      .to.emit(host, "Guardian")
      .withArgs(await host.host(), guardianAccount, 18n, 1n);

    expect(await host.isGuardianAddress(guardianAddress)).to.be.true;
  });

  it("guard IDs are correctly distinguished from other node types", async () => {
    const revokeId = await guard("revoke");
    const depositId = await cmd("deposit");
    const appointId = await cmd("appoint");

    expect(await utils.testIsGuard(revokeId)).to.be.true;
    expect(await utils.testIsGuard(depositId)).to.be.false;
    expect(await utils.testIsGuard(appointId)).to.be.false;
  });

});
