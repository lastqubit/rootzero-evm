import { expect } from "chai";
import { ethers } from "ethers";
import { commandId, deploy, getSigner, hostId } from "./helpers/setup.js";
import {
  blockKey, concat, encodeAssetAmountBlock, encodeAssetBlock, encodeBlock,
  encodeContextBlock, encodeLabelBlock, encodeStringBlock, endpointSpecs, Keys,
} from "./helpers/blocks.js";
import "./helpers/matchers.js";

describe("Pool admin commands", () => {
  const first = ethers.toBeHex(1, 32), second = ethers.toBeHex(2, 32);
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
    const pair = concat(block(first, 0n), block(second, ethers.MaxUint256));

    it(`${method} publishes its admin descriptor, label, and pair grouping`, async () => {
      const id = await commandId(method + "(bytes)", host, 2n);
      await expect(host.deploymentTransaction()).to.emitEndpoint(host).withArgs(id, ...endpointSpecs({ input: key, inputHint: size, inputCodes: 0x20000002n | (0x20000008n << 32n) | ((method === "addPool" ? 4n : 5n) << 64n), admin: true }));
      await expect(host.deploymentTransaction()).to.emitAnnotation(host)
        .withArgs(id, encodeLabelBlock(ethers.ZeroHash, method));
      await expect(host.deploymentTransaction()).to.emitAnnotation(host)
        .withArgs(id, encodeBlock(blockKey("#groups"), encodeStringBlock("#input as (first, second)")));
    });

    it(`${method} decodes ordered pairs and leaves asset and quantity policy to the hook`, async () => {
      const input = concat(pair, block(second, 7n), block(second, 11n));
      const context = encodeContextBlock(admin, "0x", input);
      expect(await host[method].staticCall(context)).deep.eq(["0x", 0n]);
      const receipt = await (await host[method](context)).wait();
      const events = receipt.logs.filter((log: any) => log.topics.length).map((log: any) => host.interface.parseLog(log))
        .filter((log: any) => log?.name === event);
      expect(events.map((log: any) => Array.from(log.args))).deep.eq(add
        ? [[first, 0n, second, ethers.MaxUint256], [second, 7n, second, 11n]]
        : [[first, second], [second, second]]);
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
      const member = block(first, 1n);
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
      await expect(host[method](encodeContextBlock(admin, encodeAssetBlock(first), pair), { gasLimit: 3_000_000 }))
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
