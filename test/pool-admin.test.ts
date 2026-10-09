import { expect } from "chai";
import { ethers } from "ethers";
import { commandId, deploy, getSigner, hostId } from "./helpers/setup.js";
import {
  blockKey, concat, encodeAssetAmountBlock, encodeAssetBlock, encodeBlock,
  encodeContextBlock, encodeStringBlock, endpointSpecs, Keys,
} from "./helpers/blocks.js";
import "./helpers/matchers.js";

describe("Pool admin commands", () => {
  const a = ethers.toBeHex(1, 32), b = ethers.toBeHex(2, 32);
  let host: Awaited<ReturnType<typeof deploy>>;
  let admin: string;
  beforeEach(async () => {
    host = await deploy("TestPoolCommands", await hostId(await (await getSigner()).getAddress()));
    admin = await host.getAdminAccount();
  });

  for (const method of ["addPool", "removePool"]) {
    const add = method === "addPool";
    const key = add ? Keys.AssetAmount : Keys.Asset;
    const size = add ? 64 : 32;
    const event = add ? "PoolAdded" : "PoolRemoved";
    const block = (asset: string, amount: bigint) => add ? encodeAssetAmountBlock(asset, amount) : encodeAssetBlock(asset);
    const pair = concat(block(a, 0n), block(b, ethers.MaxUint256));

    it(`${method} publishes its admin descriptor, name, and pair grouping`, async () => {
      const id = await commandId(method + "(bytes)", host, 2n);
      const lanes = endpointSpecs({ input: key, inputHint: size, admin: true });
      lanes[1] |= BigInt(blockKey(method));
      await expect(host.deploymentTransaction()).to.emitEndpoint(host).withArgs(id, ...lanes);
      await expect(host.deploymentTransaction()).to.emitEndpoint(host)
        .withArgs(id, undefined, undefined, undefined, method);
      await expect(host.deploymentTransaction()).to.emitMetadata(host)
        .withArgs(await host.host(), encodeBlock(blockKey("#lane"), concat(ethers.toBeHex(lanes[1], 32),
          encodeStringBlock(`#${add ? "assetAmount" : "asset"}[2] as (a, b)`))));
    });

    it(`${method} decodes ordered pairs and leaves asset and quantity policy to the hook`, async () => {
      const input = concat(pair, block(b, 7n), block(b, 11n));
      const context = encodeContextBlock(admin, "0x", input);
      expect(await host[method].staticCall(context)).deep.eq(["0x", 0n]);
      const receipt = await (await host[method](context)).wait();
      const events = receipt.logs.filter((log: any) => log.topics.length).map((log: any) => host.interface.parseLog(log))
        .filter((log: any) => log?.name === event);
      expect(events.map((log: any) => Array.from(log.args))).deep.eq(add
        ? [[a, 0n, b, ethers.MaxUint256], [b, 7n, b, 11n]]
        : [[a, b], [b, b]]);
      expect(await host.calls()).eq(2n);
    });

    it(`${method} authorizes the account and caller even for empty batches`, async () => {
      for (const input of ["0x", pair]) {
        const context = encodeContextBlock(admin, "0x", input);
        await expect(host.connect(await getSigner(1))[method](context)).revertedWithCustomError(host, "AccessDenied");
        await expect(host[method](encodeContextBlock(ethers.ZeroHash, "0x", input)))
          .revertedWithCustomError(host, "AccessDenied");
      }
      expect(await host[method].staticCall(encodeContextBlock(admin, "0x", "0x"))).deep.eq(["0x", 0n]);
      expect(await host.calls()).eq(0n);
    });

    it(`${method} rejects malformed or incomplete pairs and rolls back earlier pairs`, async () => {
      const member = block(a, 1n);
      const cases: [string, string][] = [
        [member, "InvalidBlock"],
        [concat(member, encodeBlock(Keys.Bytes, "0x")), "InvalidBlock"],
        [concat(member, encodeBlock(key, "0x" + "ab".repeat(size - 1))), "InvalidBlock"],
        [ethers.dataSlice(pair, 0, ethers.dataLength(pair) - 1), "OutOfBounds"],
      ];
      for (const [malformed, error] of cases) {
        for (const input of [malformed, concat(pair, malformed)]) {
          await expect(host[method](encodeContextBlock(admin, "0x", input), { gasLimit: 3_000_000 }))
            .revertedWithCustomError(host, error);
          expect(await host.calls()).eq(0n);
        }
      }
      await expect(host[method](encodeContextBlock(admin, encodeAssetBlock(a), pair), { gasLimit: 3_000_000 }))
        .revertedWithCustomError(host, "InvalidBlock");
      expect(await host.calls()).eq(0n);
    });

    it(`${method} propagates a later hook failure and rolls back the batch`, async () => {
      await host.failAt(2);
      await expect(host[method](encodeContextBlock(admin, "0x", concat(pair, pair)), { gasLimit: 3_000_000 }))
        .revertedWithCustomError(host, "HookRejected");
      expect(await host.calls()).eq(0n);
    });
  }
});
