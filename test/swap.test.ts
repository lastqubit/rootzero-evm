import { decodeAnnotationLog } from "./helpers/annotation-logs.js";
import { expect } from "chai";
import { ethers } from "ethers";
import { deploy, getSigner, hostId, commandId } from "./helpers/setup.js";
import {
  concat, encodeActionBlock, encodeAssetBlock, encodeBlock, encodeBytesBlock,
  encodeContextBlock, encodeOutputBlock, encodeLabelBlock, encodeListBlock, encodePositionBlock,
  encodeSwapBlock, encodeUserAccount, endpointSpecs, exactSpec, Keys, pad32,
} from "./helpers/blocks.js";
import "./helpers/matchers.js";

describe("Swap commands", () => {
  const asset = ethers.toBeHex(1, 32), middle = ethers.toBeHex(2, 32), output = ethers.toBeHex(3, 32);
  const counterparty = ethers.toBeHex(4, 32);
  let host: Awaited<ReturnType<typeof deploy>>;
  let account: string;
  beforeEach(async () => {
    const commander = await (await getSigner()).getAddress();
    // Distinguish the context account from the authorized command caller.
    account = encodeUserAccount(await (await getSigner(1)).getAddress());
    host = await deploy("TestSwapCommands", await hostId(commander), counterparty);
    await host.configure(0n, 0n);
  });

  for (const method of ["swapExactIn", "swapExactOut"]) {
    const exactIn = method === "swapExactIn";
    const specifiedAsset = exactIn ? asset : output;
    const finalHop = exactIn ? output : asset;
    it(`${method} publishes the shared SWAP input, POSITION output lane codes and label without duplicate action metadata`, async () => {
      const id = await commandId(method + "(bytes)", host);
      await expect(host.deploymentTransaction()).to.emitEndpoint(host).withArgs(id,
        ...endpointSpecs({ input: Keys.Swap, inputHint: 256, output: exactSpec(Keys.Position, 160) | 80n }));
      await expect(host.deploymentTransaction()).to.emitAnnotation(host).withArgs(id, encodeLabelBlock(ethers.ZeroHash, method));
      const receipt = await host.deploymentTransaction().wait();
      expect(receipt.logs.flatMap((log: any) => decodeAnnotationLog(log))
        .some((value: { entity: bigint; data: string }) => value.entity === id && value.data === encodeActionBlock(80n))).eq(false);
    });

    const result = (start: string, quantity: bigint, end: string, returned: bigint) => exactIn
      ? encodePositionBlock(end, returned, start, quantity, counterparty)
      : encodePositionBlock(start, quantity, end, returned, counterparty);
    const callsFrom = (receipt: any) => receipt.logs.filter((log: any) => log.topics.length > 0)
      .map((log: any) => host.interface.parseLog(log)).filter((log: any) => log?.name === "SwapCalled")
      .map((log: any) => Array.from(log.args));

    it(`${method} walks ordered hops, propagates quantities and builds one aggregate position`, async () => {
      await host.configure(3n, 0n);
      const other = ethers.toBeHex(5, 32);
      const routes = [[finalHop], [middle, other, finalHop], [middle, specifiedAsset, middle, finalHop]];
      for (const hops of routes) {
        const quantity = 100n;
        const delta = exactIn ? -3n : 3n;
        const context = encodeContextBlock(account, "0x", encodeSwapBlock(specifiedAsset, quantity, ...hops));
        const expectedOutput = result(specifiedAsset, quantity, finalHop, quantity + delta * BigInt(hops.length));
        expect(await host[method].staticCall(context)).deep.eq([expectedOutput, 0n]);
        const receipt = await (await host[method](context)).wait();
        expect(callsFrom(receipt)).deep.eq(hops.map((hop, i) => [
          exactIn, i === 0 ? specifiedAsset : hops[i - 1], quantity + delta * BigInt(i), hop,
        ]));
        expect(receipt.logs.filter((log: any) => !log.topics.length).map((log: any) => log.data)).deep.eq([
          concat(pad32(await commandId(method + "(bytes)", host)), encodeOutputBlock(expectedOutput)),
        ]);
      }
      expect(await host.calls()).eq(8n);
    });

    it(`${method} preserves full-width quantities and logs the aggregate output`, async () => {
      const max96 = (1n << 96n) - 1n;
      for (const quantity of [0n, max96, max96 + 1n, ethers.MaxUint256]) {
        const context = encodeContextBlock(account, "0x", encodeSwapBlock(specifiedAsset, quantity, middle, finalHop));
        const expectedOutput = result(specifiedAsset, quantity, finalHop, quantity);
        expect(await host[method].staticCall(context)).deep.eq([expectedOutput, 0n]);
        const receipt = await (await host[method](context)).wait();
        const logs = receipt.logs.filter((log: any) => log.topics.length === 0);
        expect(logs).to.have.length(1);
        expect(logs[0].data).eq(concat(pad32(await commandId(method + "(bytes)", host)), encodeOutputBlock(expectedOutput)));
      }
    });

    it(`${method} accepts zero hops without calling a hook and logs the equal-sided position`, async () => {
      await host.configure(0n, 1n); // Any hook call would revert.
      for (const quantity of [0n, 1n, ethers.MaxUint256]) {
        const context = encodeContextBlock(account, "0x", encodeSwapBlock(specifiedAsset, quantity));
        const expectedOutput = result(specifiedAsset, quantity, specifiedAsset, quantity);
        expect(await host[method].staticCall(context)).deep.eq([expectedOutput, 0n]);
        const receipt = await (await host[method](context)).wait();
        expect(callsFrom(receipt)).deep.eq([]);
        expect(receipt.logs.map((log: any) => log.data)).deep.eq([
          concat(pad32(await commandId(method + "(bytes)", host)), encodeOutputBlock(expectedOutput)),
        ]);
      }
      expect(await host.calls()).eq(0n);
    });

    it(`${method} rejects malformed routes and rolls back earlier hops`, async () => {
      const valid = encodeAssetBlock(finalHop);
      const badHops: [string, string][] = [
        [encodeBlock(Keys.Node, pad32(1n)), "InvalidBlock"],
        ["0xff", "InvalidBlock"],
        [encodeBlock(Keys.Asset, "0x"), "InvalidBlock"],
        [ethers.dataSlice(valid, 0, ethers.dataLength(valid) - 1), "OutOfBounds"],
      ];
      for (const [bad, error] of badHops) {
        for (const hops of [bad, concat(valid, bad)]) {
          const input = encodeBlock(Keys.Swap, concat(specifiedAsset, pad32(10n), encodeListBlock(hops)));
          await expect(host[method](encodeContextBlock(account, "0x", input), { gasLimit: 3_000_000 }))
            .revertedWithCustomError(host, error);
          expect(await host.calls()).eq(0n);
        }
      }
    });

    it(`${method} batches positions in input order and accepts an empty batch`, async () => {
      const emptyContext = encodeContextBlock(account, "0x", "0x");
      expect(await host[method].staticCall(emptyContext)).deep.eq(["0x", 0n]);
      expect((await (await host[method](emptyContext)).wait()).logs.map((log: any) => log.data))
        .deep.eq([concat(pad32(await commandId(method + "(bytes)", host)), encodeOutputBlock("0x"))]);
      const input = concat(encodeSwapBlock(specifiedAsset, 10n, middle), encodeSwapBlock(middle, 20n, finalHop));
      const context = encodeContextBlock(account, "0x", input);
      const expectedOutput = concat(result(specifiedAsset, 10n, middle, 10n), result(middle, 20n, finalHop, 20n));
      expect(await host[method].staticCall(context)).deep.eq([expectedOutput, 0n]);
      const receipt = await (await host[method](context)).wait();
      expect(callsFrom(receipt)).deep.eq([
        [exactIn, specifiedAsset, 10n, middle],
        [exactIn, middle, 20n, finalHop],
      ]);
      expect(receipt.logs.filter((log: any) => !log.topics.length).map((log: any) => log.data)).deep.eq([
        concat(pad32(await commandId(method + "(bytes)", host)), encodeOutputBlock(expectedOutput))]);
      expect(receipt.logs.map((log: any) => log.topics.length === 0)).deep.eq([false, false, true]);
      expect(await host.calls()).eq(2n);
    });

    it(`${method} rejects malformed SWAP framing atomically`, async () => {
      const valid = encodeSwapBlock(asset, 1n, output);
      const wrap = (list: string) => encodeBlock(Keys.Swap, concat(asset, pad32(1n), list));
      const cases: [string, string][] = [
        [wrap(encodeBytesBlock(encodeAssetBlock(output))), "InvalidBlock"],
        [wrap(concat(encodeListBlock(encodeAssetBlock(output)), "0xff")), "InvalidBlock"],
        [ethers.dataSlice(valid, 0, ethers.dataLength(valid) - 1), "OutOfBounds"],
      ];
      for (const [bad, error] of cases) {
        for (const input of [bad, concat(valid, bad)]) {
          await expect(host[method](encodeContextBlock(account, "0x", input), { gasLimit: 3_000_000 }))
            .revertedWithCustomError(host, error);
          expect(await host.calls()).eq(0n);
        }
      }
    });

    it(`${method} enforces caller access and propagates hook failures`, async () => {
      const context = encodeContextBlock(account, "0x", encodeSwapBlock(asset, 1n, output));
      await expect(host.connect(await getSigner(1))[method](context)).revertedWithCustomError(host, "AccessDenied");
      await host.configure(0n, 1n);
      await expect(host[method](context)).revertedWithCustomError(host, "HookRejected");
      expect(await host.calls()).eq(0n);
      await host.configure(0n, 2n);
      const multi = encodeContextBlock(account, "0x", encodeSwapBlock(specifiedAsset, 10n, middle, finalHop));
      await expect(host[method](multi, { gasLimit: 3_000_000 })).revertedWithCustomError(host, "HookRejected");
      expect(await host.calls()).eq(0n);
    });
  }
});
