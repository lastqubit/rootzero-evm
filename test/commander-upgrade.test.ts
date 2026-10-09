import { expect } from "chai";
import { ethers } from "ethers";
import { commandId, deploy, getProvider, getSigner } from "./helpers/setup.js";
import {
  concat, encodeAccountBlock, encodeAssetAmountBlock, encodeBalanceConstraintsBlock,
  encodeBootstrapBlock, encodeNodeBlock, encodeStepBlock, encodeUserAccount,
} from "./helpers/blocks.js";
import {
  authorizeCommander, commanderCashout, commanderCodeSize, commanderDeadline,
  commanderRoundtrip, deployCommanderPair, upgradeCommander,
} from "./helpers/commander-proxy.js";
import "./helpers/matchers.js";

describe("Main-style commander upgrade", function () {
  this.timeout(120_000);

  it("matches direct deposit, local/external pipelines, cashout and balance logs", async () => {
    const { direct, proxy, implementation, owner } = await deployCommanderPair();
    const account = encodeUserAccount(owner);
    const remote = await deploy("TestRemoteCommand");
    const remoteId = await commandId("noop(bytes)", remote);
    const observations: string[][] = [];
    for (const host of [direct, proxy]) {
      const native = await host.nativeAsset();
      expect(await host.hostAddr()).eq(await host.getAddress());
      expect(await host.owner()).eq(owner);
      // Enforce the production code-size limit despite the generous test network.
      expect(await commanderCodeSize(host === proxy ? implementation : host))
        .at.most(24_576);
      await host.rootzero("0x", commanderDeadline, { value: 1_000n });
      await authorizeCommander(host, [remoteId]);
      const local = await (await host.rootzero(await commanderRoundtrip(host, 4), commanderDeadline)).wait();
      await host.rootzero(await commanderRoundtrip(host, 2, remoteId), commanderDeadline);
      expect(await host.balanceOf(account, native)).eq(1_000n);
      await host.rootzero(await commanderCashout(host, 7n), commanderDeadline);
      expect(await host.balanceOf(account, native)).eq(993n);
      expect(await (await getProvider()).getBalance(await host.getAddress())).eq(993n);
      // The local roundtrip emits identical account-balance records at each host.
      observations.push(local.logs.map((log: any) => log.data));
    }
    expect(observations[1]).deep.eq(observations[0]);
  });

  it("preserves balances, access, guardians and pending ownership while adding an inherited local command", async () => {
    const { proxy, implementation, owner } = await deployCommanderPair();
    const account = encodeUserAccount(owner);
    const native = await proxy.nativeAsset();
    const nextOwner = await (await getSigner(1)).getAddress();
    const remote = await deploy("TestRemoteCommand");
    const remoteId = await commandId("noop(bytes)", remote);
    const appoint = await commandId("appoint(bytes)", proxy, 2n);
    await proxy.rootzero("0x", commanderDeadline, { value: 1_000n });
    await authorizeCommander(proxy, [remoteId, appoint]);
    await proxy.govern(encodeStepBlock(appoint, 0n, encodeAccountBlock(account)), commanderDeadline);
    await proxy.transferOwnership(nextOwner);
    const oldHost = await proxy.host();
    const oldAccount = await proxy.hostAccount();
    const addedPipeline = await commanderCashout(proxy, 7n, true);
    await expect(proxy.rootzero(addedPipeline, commanderDeadline)).revertedWithCustomError(proxy, "AccessDenied");

    const upgraded = await upgradeCommander(proxy);
    expect(await upgraded.upgradeMarker()).eq(42n);
    expect(await upgraded.host()).eq(oldHost);
    expect(await upgraded.hostAccount()).eq(oldAccount);
    expect(await upgraded.owner()).eq(owner);
    expect(await upgraded.pendingOwner()).eq(nextOwner);
    await upgraded.revoke(encodeNodeBlock(appoint));
    expect(await upgraded.isAuthorized(appoint)).eq(false);
    expect(await upgraded.isAuthorized(remoteId)).eq(true);
    expect(await upgraded.balanceOf(account, native)).eq(1_000n);
    expect(await implementation.balanceOf(account, native)).eq(0n);
    expect(await upgraded.isAuthorized(await commandId("debitAccount(bytes)", upgraded))).eq(false);
    await upgraded.rootzero(addedPipeline, commanderDeadline);
    expect(await upgraded.balanceOf(account, native)).eq(993n);
    await upgraded.rootzero(await commanderRoundtrip(upgraded, 4), commanderDeadline);
    await upgraded.rootzero(await commanderRoundtrip(upgraded, 2, remoteId), commanderDeadline);

    // A newly deployed external command can also be admitted after the upgrade.
    const more = await deploy("TestRemoteCommand");
    const moreId = await commandId("noop(bytes)", more);
    await authorizeCommander(upgraded, [moreId]);
    await upgraded.rootzero(await commanderRoundtrip(upgraded, 1, moreId), commanderDeadline);
    expect(await upgraded.balanceOf(account, native)).eq(993n);
    await upgraded.connect(await getSigner(1)).acceptOwnership();
    expect(await upgraded.owner()).eq(nextOwner);
  });

  it("locks initialization and rejects unauthorized or incorrectly bound upgrades", async () => {
    const { proxy, implementation, owner } = await deployCommanderPair();
    const next = await deploy("TestCommanderUpgradeableV2", await proxy.getAddress());
    expect(await commanderCodeSize(next)).at.most(24_576);
    await expect(implementation.initialize.staticCall(owner)).revertedWithCustomError(implementation, "InvalidInitialization");
    await expect(proxy.initialize.staticCall(owner)).revertedWithCustomError(proxy, "InvalidInitialization");
    await expect(proxy.connect(await getSigner(1)).upgradeToAndCall.staticCall(await next.getAddress(), "0x"))
      .revertedWithCustomError(proxy, "OwnableUnauthorizedAccount");
    await expect(implementation.upgradeToAndCall.staticCall(await next.getAddress(), "0x"))
      .revertedWithCustomError(implementation, "UUPSUnauthorizedCallContext");
    const wrong = await deploy("TestCommanderUpgradeableV2", ethers.ZeroAddress);
    await expect(proxy.upgradeToAndCall.staticCall(await wrong.getAddress(), "0x"))
      .revertedWithCustomError(proxy, "WrongExecutionAddress");
    const upgraded = await upgradeCommander(proxy);
    await expect(upgraded.initializeV2.staticCall()).revertedWithCustomError(upgraded, "InvalidInitialization");
  });

  it("keeps rollback, deadlines, size limits and transient reentrancy protection after upgrade", async () => {
    const { direct, proxy, owner } = await deployCommanderPair();
    const upgraded = await upgradeCommander(proxy);
    for (const host of [direct, upgraded]) {
      const asset = await host.nativeAsset();
      const account = encodeUserAccount(owner);
      await host.rootzero("0x", commanderDeadline, { value: 100n });
      const failing = concat(
        encodeStepBlock(await commandId("bootstrap(bytes)", host), 0n,
          encodeBootstrapBlock(0n, encodeAssetAmountBlock(asset, 7n))),
        encodeStepBlock(await commandId("checkBalance(bytes)", host), 0n,
          encodeBalanceConstraintsBlock(asset, 8n, 9n)),
        encodeStepBlock(await commandId("creditAccount(bytes)", host), 0n, "0x"),
      );
      await expect(host.rootzero(failing, commanderDeadline)).revertedWithCustomError(host, "OutOfRange");
      expect(await host.balanceOf(account, asset)).eq(100n);
      await expect(host.rootzero.staticCall("0x", 0)).revertedWithCustomError(host, "Expired");
      await expect(host.rootzero.staticCall("0x" + "00".repeat(4097), commanderDeadline)).revertedWithCustomError(host, "InvalidSteps");
      const receiver = await deploy("TestCommanderReentrantReceiver");
      await receiver.withdraw(await host.getAddress(), await commanderCashout(host, 7n), { value: 7n });
      expect(await receiver.reentryError()).eq(ethers.id("ReentrancyGuardReentrantCall()").slice(0, 10));
      expect(await host.balanceOf(encodeUserAccount(await receiver.getAddress()), asset)).eq(0n);
      // The guard and budget recover for a later transaction.
      await host.rootzero(await commanderRoundtrip(host, 1), commanderDeadline);
      expect(await host.balanceOf(account, asset)).eq(100n);
    }
  });
});
