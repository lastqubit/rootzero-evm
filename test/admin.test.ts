import { expectNoExecutionRecords, expectTrustLogs } from "./helpers/scoped-logs.js";
import { expect } from "chai";
import { ethers } from "ethers";
import { commandId, deploy, getSigner, getProvider, hostId } from "./helpers/setup.js";
import "./helpers/matchers.js";
import {
  Keys,
  endpointSpecs,
  exactSpec,
  encodeEntityBlock, encodeAccountBlock, encodeAssetBlock, encodeAllowanceBlock,
  encodeCallBlock, encodeContextBlock, encodeSchemaBlock, concat
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
      : ["authorize", "unauthorize", "appoint", "dismiss", "allowance"].includes(method)
        ? 2n
        : 0n;
    return commandId(host.interface.getFunction(method)!.selector, host, flags);
  }

  describe("admin runner", () => {
    for (const method of [
      "authorize", "unauthorize", "appoint", "dismiss", "allowance", "executePayable",
    ]) {
      it(`${method} authorizes even an empty batch`, async () => {
        await expect(callAs(1, method, adminCtx("0x")))
          .to.be.revertedWithCustomError(host, "AccessDenied");
        await expect(callAs(0, method, userCtx(ethers.ZeroHash, "0x")))
          .to.be.revertedWithCustomError(host, "AccessDenied");
        expect(await host[method].staticCall(...adminCtx("0x")))
          .to.deep.equal(["0x", 0n]);
      });
    }

    it("returns the full native budget for an empty payable batch", async () => {
      expect(await host.executePayable.staticCall(...adminCtx("0x"), { value: 7n }))
        .to.deep.equal(["0x", 7n]);
    });

    it("shares the native budget across callbacks and returns only the remainder", async () => {
      const target = await deploy("TestExecuteTarget");
      const targetId = await hostId(await target.getAddress());
      const data = target.interface.encodeFunctionData("ping", [1n, "0xab"]);
      const input = concat(
        encodeCallBlock(targetId, 3n, data),
        encodeCallBlock(targetId, 5n, data),
      );

      expect(await host.executePayable.staticCall(...adminCtx(input), { value: 10n }))
        .to.deep.equal(["0x", 2n]);
      await expect(callAs(0, "executePayable", adminCtx(input), { value: 7n }))
        .to.be.revertedWithCustomError(host, "InsufficientValue");
    });
  });

  // â”€â”€ Authorize â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  describe("authorize", () => {
    it("exposes its command id internally", async () => {
      expect(await host.testAuthorizeId()).to.equal(await cmd("authorize"));
    });

    it("authorizes a node and logs Access", async () => {
      const nodeId = await hostId(await (await getSigner(4)).getAddress());
      const input = encodeEntityBlock(nodeId);
      await expectTrustLogs(callAs(0, "authorize", adminCtx(input)), [nodeId], true);
      expect(await host.isAuthorized(nodeId)).to.be.true;
    });

    it("authorizes multiple nodes from multiple NODE blocks", async () => {
      const node1 = await hostId(await (await getSigner(5)).getAddress());
      const node2 = await hostId(await (await getSigner(6)).getAddress());
      const input = concat(encodeEntityBlock(node1), encodeEntityBlock(node2));
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

      await expect(callAs(0, "authorize", adminCtx(encodeEntityBlock(foreignNode))))
        .to.be.revertedWithCustomError(host, "InvalidId");
      // Opaque representation (0x02) with the Node category (0x02).
      await expect(callAs(0, "authorize", adminCtx(encodeEntityBlock((0x0202n << 240n) | 1n))))
        .to.be.revertedWithCustomError(host, "InvalidId");
    });

    it("reverts AccessDenied when a trusted non-commander tries to authorize", async () => {
      const trustedSigner = await getSigner(1);
      const trustedAddress = await trustedSigner.getAddress();
      await callAs(0, "authorize", adminCtx(encodeEntityBlock(await hostId(trustedAddress))));

      await expect(callAs(1, "authorize", adminCtx(encodeEntityBlock(0xddd001n))))
        .to.be.revertedWithCustomError(host, "AccessDenied");
    });

    it("reverts AccessDenied for non-admin account", async () => {
      const fakeAdmin = ethers.zeroPadValue("0x01", 32);
      const input = encodeEntityBlock(1n);
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

    it("revokes node and logs Access", async () => {
      const nodeId = await hostId(await (await getSigner(8)).getAddress());
      // authorize first
      await callAs(0, "authorize", adminCtx(encodeEntityBlock(nodeId)));
      // then unauthorize
      await expectTrustLogs(callAs(0, "unauthorize", adminCtx(encodeEntityBlock(nodeId))), [nodeId], false);
      expect(await host.isAuthorized(nodeId)).to.be.false;
    });

    it("reverts AccessDenied for non-admin account", async () => {
      const fakeAdmin = ethers.zeroPadValue("0x02", 32);
      const input = encodeEntityBlock(1n);
      await expect(callAs(0, "unauthorize", userCtx(fakeAdmin, input)))
        .to.be.revertedWithCustomError(host, "AccessDenied");
    });

    it("accepts an empty input batch", async () => {
      await callAs(0, "unauthorize", adminCtx("0x"));
    });
  });

  describe("appoint", () => {
    it("assigns the guardian role to a user account and logs input", async () => {
      const guardianAddress = await (await getSigner(2)).getAddress();
      const guardianAccount = await utils.testToUserAccount(guardianAddress);
      const input = encodeAccountBlock(guardianAccount);

      await expectNoExecutionRecords(callAs(0, "appoint", adminCtx(input)));

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
    it("removes the guardian role and logs input", async () => {
      const guardianAddress = await (await getSigner(3)).getAddress();
      const guardianAccount = await utils.testToUserAccount(guardianAddress);
      const input = encodeAccountBlock(guardianAccount);

      await callAs(0, "appoint", adminCtx(input));

      await expectNoExecutionRecords(callAs(0, "dismiss", adminCtx(input)));

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

  describe("trust beyond nodes", () => {
    it("authorizes and unauthorizes any non-zero ID kind, recording Trust changes", async () => {
      // An opaque asset ID: representation 0x02, category Asset (0x03).
      const asset = (0x0203n << 240n) | 0x1234n;
      await expectTrustLogs(callAs(0, "authorize", adminCtx(encodeEntityBlock(asset))), [asset], true);
      expect(await host.isAuthorized(asset)).eq(true);
      await callAs(0, "unauthorize", adminCtx(encodeEntityBlock(asset)));
      expect(await host.isAuthorized(asset)).eq(false);
    });

    it("rejects the zero ID, the always-trusted native assets and non-local node IDs", async () => {
      await expect(callAs(0, "authorize", adminCtx(encodeEntityBlock(0n))))
        .to.be.revertedWithCustomError(host, "InvalidId");
      const chain = BigInt(await (await deploy("TestUtils")).testToChain());
      for (const native of [chain, 0x0103n << 240n]) {
        for (const method of ["authorize", "unauthorize"]) {
          await expect(callAs(0, method, adminCtx(encodeEntityBlock(native))))
            .to.be.revertedWithCustomError(host, "InvalidId");
        }
      }
      const foreignNode = (0x03020200n << 224n) | (99999n << 192n) | 0xabcn;
      await expect(callAs(0, "authorize", adminCtx(encodeEntityBlock(foreignNode))))
        .to.be.revertedWithCustomError(host, "InvalidId");
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

  describe("executePayable", () => {
    it("checks full-width CALL value instead of extracting a resource lane", async () => {
      const target = await deploy("TestExecuteTarget");
      const targetId = await hostId(await target.getAddress());
      const data = target.interface.encodeFunctionData("ping", [1n, "0xab"]);
      for (const value of [1n << 128n, (7n << 128n) | 13n, ethers.MaxUint256]) {
        const input = encodeCallBlock(targetId, value, data);
        await expect(callAs(0, "executePayable", adminCtx(input), { value: 13n }))
          .to.be.revertedWithCustomError(host, "InsufficientValue");
      }
    });

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

    it("right-pads short selectors in failed raw cursor calls", async () => {
      const target = await deploy("TestExecuteTarget");
      const addr = await target.getAddress();
      const targetId = await hostId(addr);
      const errors = new ethers.Interface(["error FailedCall(address addr, bytes4 selector, bytes err)"]);
      for (const data of ["0x", "0xff", "0xffab", "0xffabcd", "0xffabcdef", "0xffabcdef12"]) {
        // The following block supplies nonzero bytes immediately after the selected input.
        const input = concat(encodeCallBlock(targetId, 0n, data), encodeCallBlock(targetId, 0n, "0x11223344"));
        let failure: string | undefined;
        try { await callAs(0, "executePayable", adminCtx(input)); }
        catch (error: any) { failure = error.data ?? error.info?.error?.data; }
        const selector = (data.slice(0, 10) + "00000000").slice(0, 10);
        expect(failure).eq(errors.encodeErrorResult("FailedCall", [addr, selector, "0x"]));
      }
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

      const asset = (0x0203n << 240n) | 0x5678n;
      const targetArgs = [encodeContextBlock(await target.getAdminAccount(), "0x", encodeEntityBlock(asset))];
      const calldata = target.interface.encodeFunctionData("authorize", targetArgs);
      const input = encodeCallBlock(await hostId(await target.getAddress()), 0n, calldata);

      await (await source.executePayable(encodeContextBlock(sourceAdminAccount, "0x", input))).wait();
      expect(await target.isAuthorized(asset)).eq(true);
    });

    it("processes multiple CALL blocks in one input", async () => {
      const source = await deploy("TestCommanderHost", await hostId(commander));
      const sourceAdminAccount = await source.getAdminAccount();
      const targetA = await deploy("TestHost", await source.host());
      const targetB = await deploy("TestHost", await source.host());
      const assetA = (0x0203n << 240n) | 0xaan;
      const assetB = (0x0203n << 240n) | 0xbbn;

      const calldataA = targetA.interface.encodeFunctionData(
        "authorize",
        [encodeContextBlock(await targetA.getAdminAccount(), "0x", encodeEntityBlock(assetA))]
      );
      const calldataB = targetB.interface.encodeFunctionData(
        "authorize",
        [encodeContextBlock(await targetB.getAdminAccount(), "0x", encodeEntityBlock(assetB))]
      );

      const tx = await source.executePayable(encodeContextBlock(sourceAdminAccount, "0x", concat(
        encodeCallBlock(await hostId(await targetA.getAddress()), 0n, calldataA),
        encodeCallBlock(await hostId(await targetB.getAddress()), 0n, calldataB)
      )));

      await tx.wait();
      expect([await targetA.isAuthorized(assetA), await targetB.isAuthorized(assetB)]).deep.eq([true, true]);
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



