import { expect } from "chai";
import { ethers } from "ethers";
import { deploy, getSigner, hostId, commandId } from "./helpers/setup.js";
import {
  concat, encodeActionBlock, encodeAssetBlock, encodeBlock, encodeBytesBlock,
  encodeContextBlock, encodeLabelBlock, encodeListBlock, encodePositionBlock,
  encodeSwapBlock, encodeUserAccount, endpointDescriptor, exactSpec, Keys, pad32,
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
    account = encodeUserAccount(commander);
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
        endpointDescriptor({ input: Keys.Swap, inputHint: 256, output: exactSpec(Keys.Position, 160) }));
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
      expect(await host[method].staticCall(encodeContextBlock(account, "0x", "0x"))).deep.eq(["0x", 0n]);
      const input = concat(encodeSwapBlock(specifiedAsset, 10n, middle), encodeSwapBlock(middle, 20n, finalHop));
      const context = encodeContextBlock(account, "0x", input);
      expect(await host[method].staticCall(context)).deep.eq([concat(encodedPosition, encodedPosition), 0n]);
      const receipt = await (await host[method](context)).wait();
      const calls = receipt.logs.map((log: any) => host.interface.parseLog(log)).filter((log: any) => log?.name === "SwapCalled");
      expect(calls.map((log: any) => Array.from(log.args))).deep.eq([
        [exactIn, specifiedAsset, 10n, encodeAssetBlock(middle)],
        [exactIn, middle, 20n, encodeAssetBlock(finalHop)],
      ]);
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
