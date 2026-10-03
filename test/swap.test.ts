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
  const position = [output, ethers.MaxUint256, asset, 123n, counterparty];
  const encodedPosition = encodePositionBlock(output, ethers.MaxUint256, asset, 123n, counterparty);
  let host: Awaited<ReturnType<typeof deploy>>;
  let account: string;
  beforeEach(async () => {
    const commander = await (await getSigner()).getAddress();
    // Distinguish the context account from the authorized command caller.
    account = encodeUserAccount(await (await getSigner(1)).getAddress());
    host = await deploy("TestSwapCommands", await hostId(commander));
    await host.configure(position, false);
  });

  for (const method of ["swapExactIn", "swapExactOut"]) {
    const exactIn = method === "swapExactIn";
    const specifiedAsset = exactIn ? asset : output;
    const finalHop = exactIn ? output : asset;
    it(`${method} publishes the shared SWAP input, POSITION output, label, and Swap action`, async () => {
      const id = await commandId(method + "(bytes)", host);
      await expect(host.deploymentTransaction()).to.emit(host, "Endpoint").withArgs(await host.host(), id,
        ...endpointSpecs({ input: Keys.Swap, inputHint: 256, output: exactSpec(Keys.Position, 160) | 80n }));
      await expect(host.deploymentTransaction()).to.emit(host, "Annotation").withArgs(id, encodeLabelBlock(ethers.ZeroHash, method));
      await expect(host.deploymentTransaction()).to.emit(host, "Annotation").withArgs(id, encodeActionBlock(80n));
    });

    it(`${method} forwards full-width quantities and ordered routes and returns the hook's complete position`, async () => {
      const other = ethers.toBeHex(5, 32);
      const routes = exactIn
        ? [[output], [middle, other, output], [middle, asset, middle, output]]
        : [[asset], [other, middle, asset], [middle, asset, middle, asset]];
      for (const hops of routes) {
        const context = encodeContextBlock(account, "0x", encodeSwapBlock(specifiedAsset, ethers.MaxUint256, ...hops));
        expect(await host[method].staticCall(context)).deep.eq([encodedPosition, 0n]);
        await expect(host[method](context)).to.emit(host, "SwapCalled")
          .withArgs(exactIn, specifiedAsset, ethers.MaxUint256, concat(...hops.map(encodeAssetBlock)));
      }
    });

    it(`${method} logs the full-width hook result in an endpoint-prefixed OUTPUT block`, async () => {
      const max96 = (1n << 96n) - 1n;
      for (const [amount, debt] of [[0n, 0n], [max96, max96], [max96 + 1n, 1n], [1n, max96 + 1n]]) {
        await host.configure([output, amount, asset, debt, counterparty], false);
        const context = encodeContextBlock(account, "0x", encodeSwapBlock(specifiedAsset, 9n, finalHop));
        const expectedOutput = encodePositionBlock(output, amount, asset, debt, counterparty);
        expect(await host[method].staticCall(context)).deep.eq([expectedOutput, 0n]);
        const receipt = await (await host[method](context)).wait();
        const logs = receipt.logs.filter((log: any) => log.topics.length === 0);
        expect(logs).to.have.length(1);
        expect(logs[0].data).eq(concat(pad32(await commandId(method + "(bytes)", host)), encodeOutputBlock(expectedOutput)));
      }
    });

    it(`${method} leaves amount and route validation to the hook`, async () => {
      for (const hops of ["0x", encodeBlock(Keys.Node, pad32(1n)), "0xff"]) {
        const input = encodeBlock(Keys.Swap, concat(asset, pad32(0n), encodeListBlock(hops)));
        const context = encodeContextBlock(account, "0x", input);
        expect(await host[method].staticCall(context)).deep.eq([encodedPosition, 0n]);
        await expect(host[method](context)).to.emit(host, "SwapCalled")
          .withArgs(exactIn, asset, 0n, hops);
      }
    });

    it(`${method} batches inputs in order and accepts an empty batch`, async () => {
      const emptyContext = encodeContextBlock(account, "0x", "0x");
      expect(await host[method].staticCall(emptyContext)).deep.eq(["0x", 0n]);
      expect((await (await host[method](emptyContext)).wait()).logs.map((log: any) => log.data))
        .deep.eq([concat(pad32(await commandId(method + "(bytes)", host)), encodeOutputBlock("0x"))]);
      const input = concat(encodeSwapBlock(specifiedAsset, 10n, middle), encodeSwapBlock(middle, 20n, finalHop));
      const context = encodeContextBlock(account, "0x", input);
      expect(await host[method].staticCall(context)).deep.eq([concat(encodedPosition, encodedPosition), 0n]);
      const receipt = await (await host[method](context)).wait();
      const calls = receipt.logs.filter((log: any) => log.topics.length > 0).map((log: any) => host.interface.parseLog(log)).filter((log: any) => log?.name === "SwapCalled");
      expect(calls.map((log: any) => Array.from(log.args))).deep.eq([
        [exactIn, specifiedAsset, 10n, encodeAssetBlock(middle)],
        [exactIn, middle, 20n, encodeAssetBlock(finalHop)],
      ]);
      const stateLogs = receipt.logs.filter((log: any) => log.topics.length === 0);
      expect(stateLogs.map((log: any) => log.data)).deep.eq([
        concat(pad32(await commandId(method + "(bytes)", host)), encodeOutputBlock(concat(encodedPosition, encodedPosition)))]);
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
      await host.configure(position, true);
      await expect(host[method](context)).revertedWithCustomError(host, "HookRejected");
      expect(await host.calls()).eq(0n);
    });
  }
});
