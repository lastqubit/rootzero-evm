import { expect } from "chai";
import { ethers } from "ethers";
import { deploy, getSigner, guardId } from "./helpers/setup.js";
import { blockKey, concat, encodeAssetAmountBlock, encodeAssetBlock, encodeBlock, encodeContextBlock,
  encodeInputBlock, encodeStringBlock, encodeUserAccount, exactSpec, Keys } from "./helpers/blocks.js";
import "./helpers/matchers.js";

describe("UpdatePool guard", () => {
  const a = ethers.toBeHex(1, 32), b = ethers.toBeHex(2, 32);
  const pair = (x: bigint, y: bigint) => concat(encodeAssetAmountBlock(a, x), encodeAssetAmountBlock(b, y));
  let host: Awaited<ReturnType<typeof deploy>>, guardian: any, caller: any;
  beforeEach(async () => {
    guardian = await getSigner(1);
    host = await deploy("TestUpdatePool", await guardian.getAddress());
    caller = host.connect(guardian);
    await host.seed(a, b);
  });

  it("publishes a guard identity and its named pair lane alongside admin pool commands", async () => {
    const fn = host.interface.getFunction("updatePool")!;
    expect(fn.stateMutability).eq("nonpayable");
    expect(fn.outputs).to.have.length(0);
    const id = await guardId("updatePool(bytes)", host);
    const lane = exactSpec(Keys.AssetAmount, 64) | BigInt(blockKey("updatePool"));
    await expect(host.deploymentTransaction()).to.emitEndpoint(host).withArgs(id, 0n, lane, 0n, "updatePool");
    await expect(host.deploymentTransaction()).to.emitMetadata(host).withArgs(await host.host(),
      encodeBlock(blockKey("#lane"), concat(ethers.toBeHex(lane, 32), encodeStringBlock("#assetAmount[2] as (a, b)"))));
  });

  it("passes ordered pairs to the hook and logs the complete input after replacing reserves", async () => {
    const input = concat(pair(100n, 200n), pair(7n, 9n));
    const tx = caller.updatePool(input);
    await expect(tx).to.emit(host, "PoolUpdated").withArgs(a, 100n, b, 200n);
    await expect(tx).to.emit(host, "PoolUpdated").withArgs(a, 7n, b, 9n);
    expect(await host.reserves(a, b, 0)).eq(7n);
    expect(await host.reserves(a, b, 1)).eq(9n);
    expect(await host.updates()).eq(2n);
    const receipt = await (await tx).wait();
    expect(receipt.logs.at(-1).data).eq(concat("0x04", ethers.toBeHex(await guardId("updatePool(bytes)", host), 32),
      encodeUserAccount(await guardian.getAddress()), encodeInputBlock(input)));
    expect(receipt.logs.at(-1).topics).deep.eq([]);
  });

  it("accepts empty batches and leaves zero/full-width reserve policy to the hook", async () => {
    await caller.updatePool("0x");
    expect(await host.updates()).eq(0n);
    await caller.updatePool(pair(0n, ethers.MaxUint256));
    expect(await host.reserves(a, b, 0)).eq(0n);
    expect(await host.reserves(a, b, 1)).eq(ethers.MaxUint256);
  });

  it("requires an active guardian even for empty input", async () => {
    for (const input of ["0x", pair(1n, 2n)]) {
      await expect(host.updatePool(input)).revertedWithCustomError(host, "AccessDenied");
    }
    await host.dismissTestGuardian(await guardian.getAddress());
    await expect(caller.updatePool(pair(1n, 2n))).revertedWithCustomError(host, "AccessDenied");
  });

  it("rejects incomplete or malformed pairs and rolls back earlier updates", async () => {
    const valid = pair(1n, 2n);
    const badInputs = [
      encodeAssetAmountBlock(a, 1n),
      concat(encodeAssetAmountBlock(a, 1n), encodeAssetBlock(b)),
      ethers.dataSlice(valid, 0, 143),
      encodeBlock(Keys.AssetAmount, ethers.toBeHex(1n, 32)),
      encodeContextBlock(ethers.ZeroHash, "0x", valid),
    ];
    for (const bad of badInputs) {
      await caller.updatePool(concat(valid, bad)).then(() => expect.fail("Expected revert"),
        (error: any) => expect(error.data).to.be.a("string"));
      expect(await host.updates()).eq(0n);
      expect(await host.reserves(a, b, 0)).eq(0n);
      expect(await host.reserves(a, b, 1)).eq(0n);
    }
  });

  it("propagates host pool checks and later hook failures atomically", async () => {
    await expect(caller.updatePool(concat(encodeAssetAmountBlock(b, 1n), encodeAssetAmountBlock(a, 2n))))
      .revertedWithCustomError(host, "MissingPool");
    await host.failAt(2n);
    await expect(caller.updatePool(concat(pair(1n, 2n), pair(3n, 4n))))
      .revertedWithCustomError(host, "HookRejected");
    expect(await host.updates()).eq(0n);
    expect(await host.reserves(a, b, 0)).eq(0n);
    expect(await host.reserves(a, b, 1)).eq(0n);
  });
});
