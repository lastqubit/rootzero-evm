import { ethers } from "ethers";
import { commandId, deploy, getProvider, getSigner } from "./setup.js";
import {
  concat, encodeAssetAmountBlock, encodeBalanceConstraintsBlock, encodeBootstrapBlock,
  encodeNodeBlock, encodeStepBlock,
} from "./blocks.js";

export const commanderDeadline = ethers.MaxUint256;

export async function deployCommanderPair() {
  const signer = await getSigner();
  const owner = await signer.getAddress();
  const direct = await deploy("TestCommanderDirect", owner);
  // The next two CREATEs deploy the implementation, then its initialized proxy.
  const nonce = await signer.getNonce("pending");
  const predicted = ethers.getCreateAddress({ from: owner, nonce: nonce + 1 });
  const implementation = await deploy("TestCommanderUpgradeable", predicted);
  const proxy = await deploy("TestCommanderERC1967Proxy", await implementation.getAddress(),
    implementation.interface.encodeFunctionData("initialize", [owner]));
  if (await proxy.getAddress() !== predicted) throw new Error("Unexpected commander proxy address");
  return { direct, proxy: implementation.attach(predicted), implementation, owner };
}

export async function upgradeCommander(proxy: any) {
  const next = await deploy("TestCommanderUpgradeableV2", await proxy.getAddress());
  await (await proxy.upgradeToAndCall(await next.getAddress(),
    next.interface.encodeFunctionData("initializeV2"))).wait();
  return next.attach(await proxy.getAddress());
}

export async function authorizeCommander(host: any, nodes: bigint[]) {
  const steps = encodeStepBlock(await commandId("authorize(bytes)", host, 2n), 0n,
    concat(...nodes.map(encodeNodeBlock)));
  await (await host.govern(steps, commanderDeadline)).wait();
}

export async function commanderRoundtrip(host: any, count = 0, external?: bigint) {
  const asset = await host.nativeAsset();
  const first = encodeStepBlock(await commandId("bootstrap(bytes)", host), 0n,
    encodeBootstrapBlock(0n, encodeAssetAmountBlock(asset, 7n)));
  const middle = external === undefined
    ? encodeStepBlock(await commandId("checkBalance(bytes)", host), 0n,
      encodeBalanceConstraintsBlock(asset, 7n, 7n))
    : encodeStepBlock(external, 0n, "0x");
  const last = encodeStepBlock(await commandId("creditAccount(bytes)", host), 0n, "0x");
  return concat(first, ...Array(count).fill(middle), last);
}

export async function commanderCashout(host: any, amount: bigint, debit = false) {
  const input = encodeAssetAmountBlock(await host.nativeAsset(), amount);
  return concat(
    encodeStepBlock(await commandId(debit ? "debitAccount(bytes)" : "bootstrap(bytes)", host), 0n,
      debit ? input : encodeBootstrapBlock(0n, input)),
    encodeStepBlock(await commandId("cashout(bytes)", host), 0n, "0x"),
  );
}

export async function commanderCodeSize(host: any) {
  return ethers.dataLength(await (await getProvider()).getCode(await host.getAddress()));
}
