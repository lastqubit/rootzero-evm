import { expect } from "chai";
import { ethers } from "ethers";
import { commandId, deploy, getSigner, getProvider, hostId } from "./helpers/setup.js";
import "./helpers/matchers.js";
import {
  Keys,
  endpointDescriptor,
  exactSpec,
  encodeNodeBlock, encodeAccountBlock, encodeAssetBlock, encodeAllowanceBlock,
  encodeCallBlock, encodeContextBlock, encodeLabelBlock, encodeAnnotationBlock, encodeSchemaBlock, concat
} from "./helpers/blocks.js";

describe("Admin Commands", () => {
  let host: Awaited<ReturnType<typeof deploy>>;
  let utils: Awaited<ReturnType<typeof deploy>>;
  let commander: string;
  let adminAccount: string;

  before(async () => {
    const signer = await getSigner(0);
    commander = await signer.getAddress();
    host = await deploy("TestHost", await hostId(commander));
    utils = await deploy("TestUtils");
    adminAccount = await host.getAdminAccount();
  });

  function adminCtx(input: string) {
    return [encodeContextBlock(adminAccount, "0x", input)] as const;
  }

  function userCtx(userAcc: string, input: string) {
    return [encodeContextBlock(userAcc, "0x", input)] as const;
  }

  async function callAs(signerIndex: number, method: string, ...args: unknown[]) {
    const signer = await getSigner(signerIndex);
    const callArgs = Array.isArray(args[0]) ? [...args[0], ...args.slice(1)] : args;
    return (host.connect(signer) as any)[method](...callArgs);
  }

  async function cmd(method: string) {
    const flags = method === "executePayable" ? 3n
      : ["authorize", "unauthorize", "appoint", "dismiss", "allowAsset", "denyAsset", "allowance", "annotate"].includes(method)
        ? 2n
        : 0n;
    return commandId(host.interface.getFunction(method)!.selector, host, flags);
  }

  // â”€â”€ Authorize â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  describe("authorize", () => {
    it("exposes its command id internally", async () => {
      expect(await host.testAuthorizeId()).to.equal(await cmd("authorize"));
    });

    it("authorizes a node and emits Node event", async () => {
      const nodeId = await hostId(await (await getSigner(4)).getAddress());
      const input = encodeNodeBlock(nodeId);
      await expect(callAs(0, "authorize", adminCtx(input)))
        .to.emit(host, "Node")
        .withArgs(await host.host(), nodeId, 16n, 1n);
      expect(await host.isAuthorized(nodeId)).to.be.true;
    });

    it("authorizes multiple nodes from multiple NODE blocks", async () => {
      const node1 = await hostId(await (await getSigner(5)).getAddress());
      const node2 = await hostId(await (await getSigner(6)).getAddress());
      const input = concat(encodeNodeBlock(node1), encodeNodeBlock(node2));
      await callAs(0, "authorize", adminCtx(input));
      expect(await host.isAuthorized(node1)).to.be.true;
      expect(await host.isAuthorized(node2)).to.be.true;
    });

    it("rejects foreign and opaque node IDs", async () => {
      const provider = await getProvider();
      const network = await provider.getNetwork();
      const address = await (await getSigner(7)).getAddress();
      const foreignNode = (0x03020200n << 224n)
        | ((network.chainId + 1n) << 192n)
        | BigInt(address);

      await expect(callAs(0, "authorize", adminCtx(encodeNodeBlock(foreignNode))))
        .to.be.revertedWithCustomError(host, "InvalidId");
      await expect(callAs(0, "authorize", adminCtx(encodeNodeBlock(1n))))
        .to.be.revertedWithCustomError(host, "InvalidId");
    });

    it("reverts AccessDenied when a trusted non-commander tries to authorize", async () => {
      const trustedSigner = await getSigner(1);
      const trustedAddress = await trustedSigner.getAddress();
      await callAs(0, "authorize", adminCtx(encodeNodeBlock(await hostId(trustedAddress))));

      await expect(callAs(1, "authorize", adminCtx(encodeNodeBlock(0xddd001n))))
        .to.be.revertedWithCustomError(host, "AccessDenied");
    });

    it("reverts AccessDenied for non-admin account", async () => {
      const fakeAdmin = ethers.zeroPadValue("0x01", 32);
      const input = encodeNodeBlock(1n);
      await expect(callAs(0, "authorize", userCtx(fakeAdmin, input)))
        .to.be.revertedWithCustomError(host, "AccessDenied");
    });

    it("accepts an empty input batch", async () => {
      await callAs(0, "authorize", adminCtx("0x"));
    });
  });

  // â”€â”€ Unauthorize â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  describe("unauthorize", () => {
    it("exposes its command id internally", async () => {
      expect(await host.testUnauthorizeId()).to.equal(await cmd("unauthorize"));
    });

    it("revokes node and emits Node event with false", async () => {
      const nodeId = await hostId(await (await getSigner(8)).getAddress());
      // authorize first
      await callAs(0, "authorize", adminCtx(encodeNodeBlock(nodeId)));
      // then unauthorize
      await expect(callAs(0, "unauthorize", adminCtx(encodeNodeBlock(nodeId))))
        .to.emit(host, "Node")
        .withArgs(await host.host(), nodeId, 17n, 0n);
      expect(await host.isAuthorized(nodeId)).to.be.false;
    });

    it("reverts AccessDenied for non-admin account", async () => {
      const fakeAdmin = ethers.zeroPadValue("0x02", 32);
      const input = encodeNodeBlock(1n);
      await expect(callAs(0, "unauthorize", userCtx(fakeAdmin, input)))
        .to.be.revertedWithCustomError(host, "AccessDenied");
    });

    it("accepts an empty input batch", async () => {
      await callAs(0, "unauthorize", adminCtx("0x"));
    });
  });

  describe("appoint", () => {
    it("assigns the guardian role to a user account and emits Guardian", async () => {
      const guardianAddress = await (await getSigner(2)).getAddress();
      const guardianAccount = await utils.testToUserAccount(guardianAddress);
      const input = encodeAccountBlock(guardianAccount);

      await expect(callAs(0, "appoint", adminCtx(input)))
        .to.emit(host, "Guardian")
        .withArgs(await host.host(), guardianAccount, 18n, 1n);

      expect(await host.isGuardianAddress(guardianAddress)).to.be.true;
    });

    it("reverts AccessDenied for non-admin account", async () => {
      const fakeAdmin = ethers.zeroPadValue("0x13", 32);
      const guardianAccount = await utils.testToUserAccount(await (await getSigner(2)).getAddress());

      await expect(callAs(0, "appoint", userCtx(fakeAdmin, encodeAccountBlock(guardianAccount))))
        .to.be.revertedWithCustomError(host, "AccessDenied");
    });

    it("reverts InvalidAccount for non-user account blocks", async () => {
      const adminAccount = await utils.testToAdminAccount(await (await getSigner(2)).getAddress());

      await expect(callAs(0, "appoint", adminCtx(encodeAccountBlock(adminAccount))))
        .to.be.revertedWithCustomError(host, "InvalidAccount");
    });

    it("rejects a user account with an embedded zero address", async () => {
      const account = await utils.testToUserAccount(ethers.ZeroAddress);

      await expect(callAs(0, "appoint", adminCtx(encodeAccountBlock(account))))
        .to.be.revertedWithCustomError(host, "ZeroAddress");
    });

    it("accepts an empty input batch", async () => {
      await callAs(0, "appoint", adminCtx("0x"));
    });
  });

  describe("dismiss", () => {
    it("removes the guardian role and emits Guardian with false", async () => {
      const guardianAddress = await (await getSigner(3)).getAddress();
      const guardianAccount = await utils.testToUserAccount(guardianAddress);
      const input = encodeAccountBlock(guardianAccount);

      await callAs(0, "appoint", adminCtx(input));

      await expect(callAs(0, "dismiss", adminCtx(input)))
        .to.emit(host, "Guardian")
        .withArgs(await host.host(), guardianAccount, 19n, 0n);

      expect(await host.isGuardianAddress(guardianAddress)).to.be.false;
    });

    it("reverts AccessDenied for non-admin account", async () => {
      const fakeAdmin = ethers.zeroPadValue("0x14", 32);
      const guardianAccount = await utils.testToUserAccount(await (await getSigner(3)).getAddress());

      await expect(callAs(0, "dismiss", userCtx(fakeAdmin, encodeAccountBlock(guardianAccount))))
        .to.be.revertedWithCustomError(host, "AccessDenied");
    });

    it("accepts an empty input batch", async () => {
      await callAs(0, "dismiss", adminCtx("0x"));
    });
  });

  // â”€â”€ AllowAsset â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  describe("allowAsset", () => {
    it("emits AllowAssetCalled for each ASSET block", async () => {
      const asset = ethers.zeroPadValue("0x01", 32);
      const input = encodeAssetBlock(asset);
      await expect(callAs(0, "allowAsset", adminCtx(input)))
        .to.emit(host, "AllowAssetCalled")
        .withArgs(asset);
    });

    it("processes multiple ASSET blocks", async () => {
      const a1 = ethers.zeroPadValue("0xA1", 32);
      const a2 = ethers.zeroPadValue("0xA2", 32);
      const input = concat(encodeAssetBlock(a1), encodeAssetBlock(a2));
      const tx = await callAs(0, "allowAsset", adminCtx(input));
      await expect(tx).to.emit(host, "AllowAssetCalled").withArgs(a1);
      await expect(tx).to.emit(host, "AllowAssetCalled").withArgs(a2);
    });

    it("reverts AccessDenied for non-admin account", async () => {
      const fakeAdmin = ethers.zeroPadValue("0x03", 32);
      await expect(callAs(0, "allowAsset", userCtx(fakeAdmin, encodeAssetBlock(ethers.zeroPadValue("0x01", 32)))))
        .to.be.revertedWithCustomError(host, "AccessDenied");
    });

    it("accepts an empty input batch", async () => {
      await callAs(0, "allowAsset", adminCtx("0x"));
    });
  });

  // â”€â”€ DenyAsset â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  describe("denyAsset", () => {
    it("emits DenyAssetCalled for each ASSET block", async () => {
      const asset = ethers.zeroPadValue("0x03", 32);
      await expect(callAs(0, "denyAsset", adminCtx(encodeAssetBlock(asset))))
        .to.emit(host, "DenyAssetCalled")
        .withArgs(asset);
    });

    it("reverts AccessDenied for non-admin", async () => {
      const fakeAdmin = ethers.zeroPadValue("0x04", 32);
      await expect(callAs(0, "denyAsset", userCtx(fakeAdmin, encodeAssetBlock(ethers.zeroPadValue("0x01", 32)))))
        .to.be.revertedWithCustomError(host, "AccessDenied");
    });

    it("accepts an empty input batch", async () => {
      await callAs(0, "denyAsset", adminCtx("0x"));
    });
  });

  // â”€â”€ Allowance â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  describe("allowance", () => {
    it("emits AllowanceCalled for each ALLOWANCE block", async () => {
      const hostId = 9999n;
      const asset  = ethers.zeroPadValue("0x05", 32);
      const amount = 1000n;
      const input = encodeAllowanceBlock(hostId, asset, amount);
      await expect(callAs(0, "allowance", adminCtx(input)))
        .to.emit(host, "AllowanceCalled")
        .withArgs(hostId, asset, amount);
    });

    it("reverts AccessDenied for non-admin", async () => {
      const fakeAdmin = ethers.zeroPadValue("0x05", 32);
      const input = encodeAllowanceBlock(1n, ethers.zeroPadValue("0x01", 32), 1n);
      await expect(callAs(0, "allowance", userCtx(fakeAdmin, input)))
        .to.be.revertedWithCustomError(host, "AccessDenied");
    });

    it("accepts an empty input batch", async () => {
      await callAs(0, "allowance", adminCtx("0x"));
    });
  });

  describe("annotate", () => {
    it("discovers annotate and publishes its default label", async () => {
      const deployment = host.deploymentTransaction();
      expect(deployment).to.not.equal(null);

      await expect(deployment!).to.emit(host, "Endpoint")
        .withArgs(
          await host.host(),
          await cmd("annotate"),
          endpointDescriptor({ input: Keys.Annotation, inputHint: 256, admin: true }),
        );
      await expect(deployment!).to.emit(host, "Annotation")
        .withArgs(await cmd("annotate"), encodeLabelBlock(ethers.ZeroHash, "annotate"));
    });

    it("emits an Annotation containing the encoded block stream", async () => {
      const entity = await cmd("deposit");
      const data = concat(encodeNodeBlock(11n), encodeNodeBlock(12n));
      const input = encodeAnnotationBlock(entity, data);

      await expect(callAs(0, "annotate", adminCtx(input)))
        .to.emit(host, "Annotation")
        .withArgs(entity, data);
    });

    it("publishes a namespaced label through an Annotation block", async () => {
      const entity = await cmd("deposit");
      const namespace = ethers.encodeBytes32String("docs");
      const data = encodeLabelBlock(namespace, "deposit v2");
      const input = encodeAnnotationBlock(entity, data);

      await expect(callAs(0, "annotate", adminCtx(input)))
        .to.emit(host, "Annotation")
        .withArgs(entity, data);
    });

    it("publishes a block schema through an Annotation block", async () => {
      const entity = await host.host();
      const name = ethers.encodeBytes32String("amount");
      const data = encodeSchemaBlock(
        exactSpec(Keys.Amount, 64),
        "{ bytes32 asset, uint amount }",
        name,
      );
      const input = encodeAnnotationBlock(entity, data);

      await expect(callAs(0, "annotate", adminCtx(input)))
        .to.emit(host, "Annotation")
        .withArgs(entity, data);
    });

    it("reverts AccessDenied for non-admin account", async () => {
      const fakeAdmin = ethers.zeroPadValue("0x06", 32);
      const input = encodeAnnotationBlock(await cmd("deposit"), encodeNodeBlock(1n));
      await expect(callAs(0, "annotate", userCtx(fakeAdmin, input)))
        .to.be.revertedWithCustomError(host, "AccessDenied");
    });

    it("accepts an empty input batch", async () => {
      await callAs(0, "annotate", adminCtx("0x"));
    });
  });

  describe("executePayable", () => {
    it("reverts AccessDenied for non-admin account", async () => {
      const fakeAdmin = ethers.zeroPadValue("0x07", 32);
      const input = encodeCallBlock(0n, 0n, "0x");
      await expect(callAs(0, "executePayable", userCtx(fakeAdmin, input)))
        .to.be.revertedWithCustomError(host, "AccessDenied");
    });

    it("executes raw calldata against a target node without prior authorization", async () => {
      const target = await deploy("TestExecuteTarget");
      const targetId = await hostId(await target.getAddress());
      const calldata = target.interface.encodeFunctionData("ping", [123n, "0x123456"]);
      const input = encodeCallBlock(targetId, 0n, calldata);

      await expect(callAs(0, "executePayable", adminCtx(input)))
        .to.emit(target, "Ping")
        .withArgs(await host.getAddress(), 0n, 123n, "0x123456");
    });

    it("ignores arbitrary successful returndata", async () => {
      const target = await deploy("TestExecuteTarget");
      const targetId = await hostId(await target.getAddress());
      const calldata = target.interface.encodeFunctionData("number");

      await callAs(0, "executePayable", adminCtx(encodeCallBlock(targetId, 0n, calldata)));
    });

    it("can govern another host through its commander host", async () => {
      const source = await deploy("TestCommanderHost", await hostId(commander));
      const sourceAdminAccount = await source.getAdminAccount();
      const target = await deploy("TestHost", await source.host());

      const asset = ethers.zeroPadValue("0x123456", 32);
      const targetArgs = [encodeContextBlock(await target.getAdminAccount(), "0x", encodeAssetBlock(asset))];
      const calldata = target.interface.encodeFunctionData("allowAsset", targetArgs);
      const input = encodeCallBlock(await hostId(await target.getAddress()), 0n, calldata);

      await expect(source.executePayable(encodeContextBlock(sourceAdminAccount, "0x", input)))
        .to.emit(target, "AllowAssetCalled")
        .withArgs(asset);
    });

    it("processes multiple CALL blocks in one input", async () => {
      const source = await deploy("TestCommanderHost", await hostId(commander));
      const sourceAdminAccount = await source.getAdminAccount();
      const targetA = await deploy("TestHost", await source.host());
      const targetB = await deploy("TestHost", await source.host());
      const assetA = ethers.zeroPadValue("0xaa", 32);
      const assetB = ethers.zeroPadValue("0xbb", 32);

      const calldataA = targetA.interface.encodeFunctionData(
        "allowAsset",
        [encodeContextBlock(await targetA.getAdminAccount(), "0x", encodeAssetBlock(assetA))]
      );
      const calldataB = targetB.interface.encodeFunctionData(
        "denyAsset",
        [encodeContextBlock(await targetB.getAdminAccount(), "0x", encodeAssetBlock(assetB))]
      );

      const tx = await source.executePayable(encodeContextBlock(sourceAdminAccount, "0x", concat(
        encodeCallBlock(await hostId(await targetA.getAddress()), 0n, calldataA),
        encodeCallBlock(await hostId(await targetB.getAddress()), 0n, calldataB)
      )));

      await expect(tx).to.emit(targetA, "AllowAssetCalled").withArgs(assetA);
      await expect(tx).to.emit(targetB, "DenyAssetCalled").withArgs(assetB);
    });

    it("can forward native value to a target node without prior authorization", async () => {
      const target = await deploy("TestExecuteTarget");
      const amount = 5n;
      const targetId = await hostId(await target.getAddress());
      const calldata = target.interface.encodeFunctionData("ping", [1n, "0xab"]);
      const input = encodeCallBlock(targetId, amount, calldata);

      await expect(callAs(0, "executePayable", adminCtx(input), { value: amount }))
        .to.emit(target, "Ping")
        .withArgs(await host.getAddress(), amount, 1n, "0xab");
    });

    it("keeps unspent admin value on the host", async () => {
      const target = await deploy("TestExecuteTarget");
      const amount = 5n;
      const surplus = 7n;
      const targetId = await hostId(await target.getAddress());
      const calldata = target.interface.encodeFunctionData("ping", [2n, "0xcd"]);
      const input = encodeCallBlock(targetId, amount, calldata);

      const provider = await getProvider();
      const hostAddr = await host.getAddress();
      const targetAddr = await target.getAddress();
      const tx = await callAs(0, "executePayable", adminCtx(input), { value: amount + surplus });
      const receipt = await tx.wait();
      if (!receipt || receipt.status === 0) throw new Error("executePayable tx reverted");
      const hostBefore = await provider.getBalance(hostAddr, receipt.blockNumber - 1);
      const hostAfter = await provider.getBalance(hostAddr, receipt.blockNumber);
      const targetBefore = await provider.getBalance(targetAddr, receipt.blockNumber - 1);
      const targetAfter = await provider.getBalance(targetAddr, receipt.blockNumber);

      expect(hostAfter - hostBefore).to.equal(surplus);
      expect(targetAfter - targetBefore).to.equal(amount);
    });

    it("can replace relocate by sending native value with empty calldata to a host", async () => {
      const target = await deploy("TestHost", await hostId(commander));
      const targetAddr = await target.getAddress();
      const targetId = await hostId(targetAddr);
      const amount = ethers.parseEther("0.001");
      const input = encodeCallBlock(targetId, amount, "0x");

      const provider = await getProvider();
      const tx = await callAs(0, "executePayable", adminCtx(input), { value: amount });
      const receipt = await tx.wait();
      if (!receipt || receipt.status === 0) throw new Error("executePayable tx reverted");
      const before = await provider.getBalance(targetAddr, receipt.blockNumber - 1);
      const after = await provider.getBalance(targetAddr, receipt.blockNumber);

      expect(after - before).to.equal(amount);
    });

    it("reverts FailedCall when the raw target call reverts", async () => {
      const target = await deploy("TestRejectEther");
      const targetId = await hostId(await target.getAddress());

      await expect(callAs(0, "executePayable", adminCtx(encodeCallBlock(targetId, 1n, "0x")), { value: 1n }))
        .to.be.revertedWithCustomError(host, "FailedCall");
    });
  });

});



