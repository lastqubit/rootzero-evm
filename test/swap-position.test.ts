import { expect } from "chai";
import { ethers } from "ethers";
import { deploy, getSigner, hostId, commandId } from "./helpers/setup.js";
import {
  concat, encodeAssetBlock, encodeBlock, encodeBytesBlock, encodeContextBlock,
  encodeListBlock, encodeOutputBlock, encodePositionBlock, encodeSwapBlock,
  encodeUserAccount, exactSpec, rangedSpec, Keys, pad32,
} from "./helpers/blocks.js";
import "./helpers/matchers.js";

describe("Position swap commands", () => {
  const asset = pad32(1n), liability = pad32(2n), middle = pad32(3n), target = pad32(4n);
  const counterparty = encodeUserAccount(ethers.toBeHex(5, 20));
  const route = (...hops: string[]) => encodeListBlock(concat(...hops.map(encodeAssetBlock)));
  const position = (amount = 100n, debt = 40n, party = counterparty) =>
    encodePositionBlock(asset, amount, liability, debt, party);
  let host: Awaited<ReturnType<typeof deploy>>;
  let account: string;

  beforeEach(async () => {
    account = encodeUserAccount(await (await getSigner(1)).getAddress());
    host = await deploy("TestSwapCommands", await hostId(await (await getSigner()).getAddress()), counterparty);
  });

  const callsFrom = (receipt: any) => receipt.logs.filter((log: any) => log.topics.length > 0)
    .map((log: any) => host.interface.parseLog(log)).filter((log: any) => log?.name === "SwapCalled")
    .map((log: any) => Array.from(log.args));

  for (const method of ["swapAssetExactInput", "swapDebtExactOutput"]) {
    const exactInput = method === "swapAssetExactInput";
    const start = exactInput ? asset : liability;
    const result = (amount: bigint, debt: bigint, hops: string[], delta = 3n) => exactInput
      ? encodePositionBlock(hops.at(-1) ?? asset, amount - delta * BigInt(hops.length), liability, debt, counterparty)
      : encodePositionBlock(asset, amount, hops.at(-1) ?? liability, debt + delta * BigInt(hops.length), counterparty);

    it(`${method} registers POSITION / LIST / POSITION metadata and its name`, async () => {
      const id = await commandId(method + "(bytes)", host);
      await expect(host.deploymentTransaction()).to.emitEndpoint(host).withArgs(id,
        exactSpec(Keys.Position, 160), rangedSpec(Keys.List, 0, 0, 128), exactSpec(Keys.Position, 160));
      await expect(host.deploymentTransaction()).to.emitEndpoint(host)
        .withArgs(id, undefined, undefined, undefined, method);
    });

    it(`${method} derives quantities from state and preserves the opposite leg across ordered hops`, async () => {
      await host.configure(3n, 0n);
      for (const hops of [[target], [middle, target], [middle, start, middle, target]]) {
        const context = encodeContextBlock(account, position(), route(...hops));
        const expected = result(100n, 40n, hops);
        expect(await host[method].staticCall(context)).deep.eq([expected, 0n]);
        const receipt = await (await host[method](context)).wait();
        expect(callsFrom(receipt)).deep.eq(hops.map((hop, i) => [exactInput,
          i === 0 ? start : hops[i - 1], (exactInput ? 100n : 40n) + (exactInput ? -3n : 3n) * BigInt(i), hop,
        ]));
        expect(receipt.logs.filter((log: any) => !log.topics.length).map((log: any) => log.data)).deep.eq([]);
      }
    });

    it(`${method} pairs mixed routes with positions in order and logs one complete batch`, async () => {
      await host.configure(3n, 0n);
      const state = concat(position(), position(200n, 80n), position(300n, 120n));
      const context = encodeContextBlock(account, state, concat(route(middle, target), route(), route(target)));
      const expected = concat(result(100n, 40n, [middle, target]), position(200n, 80n), result(300n, 120n, [target]));
      expect(await host[method].staticCall(context)).deep.eq([expected, 0n]);
      const receipt = await (await host[method](context)).wait();
      expect(callsFrom(receipt)).deep.eq([
        [exactInput, start, exactInput ? 100n : 40n, middle],
        [exactInput, middle, exactInput ? 97n : 43n, target],
        [exactInput, start, exactInput ? 300n : 120n, target],
      ]);
      expect(receipt.logs.filter((log: any) => !log.topics.length).map((log: any) => log.data)).deep.eq([]);
      expect(await host.calls()).eq(3n);
    });

    it(`${method} leaves empty routes unchanged and accepts empty batches after access checks`, async () => {
      await host.configure(0n, 1n);
      for (const [state, input] of [[position(), route()], [position(0n, ethers.MaxUint256), route()], ["0x", "0x"]]) {
        const context = encodeContextBlock(account, state, input);
        expect(await host[method].staticCall(context)).deep.eq([state, 0n]);
        const receipt = await (await host[method](context)).wait();
        expect(callsFrom(receipt)).deep.eq([]);
        expect(receipt.logs.map((log: any) => log.data)).deep.eq([]);
        await expect(host.connect(await getSigner(1))[method](context)).revertedWithCustomError(host, "AccessDenied");
      }
      expect(await host.calls()).eq(0n);
    });

    it(`${method} delegates zero, full-width, repeated-asset and zero-asset validation to the hook`, async () => {
      for (const quantity of [0n, (1n << 96n) + 1n, ethers.MaxUint256]) {
        const hops = [start, ethers.ZeroHash, target];
        const context = encodeContextBlock(account, position(quantity, quantity), route(...hops));
        expect(await host[method].staticCall(context)).deep.eq([result(quantity, quantity, hops, 0n), 0n]);
      }
    });

    it(`${method} checks every counterparty, even on empty routes, and rolls back prior hops`, async () => {
      for (const party of [ethers.ZeroHash, asset, account]) {
        for (const hops of [[], [target]]) {
          const bad = position(100n, 40n, party);
          for (const [state, input] of [[bad, route(...hops)],
            [concat(position(), bad), concat(route(middle), route(...hops))]]) {
            await expect(host[method](encodeContextBlock(account, state, input), { gasLimit: 3_000_000 }))
              .revertedWithCustomError(host, "UnexpectedValue");
            expect(await host.calls()).eq(0n);
          }
        }
      }
    });

    it(`${method} preserves matching opaque account counterparties byte for byte`, async () => {
      const opaque = "0x0201ff" + "ab".repeat(29);
      const opaqueHost = await deploy("TestSwapCommands", await hostId(await (await getSigner()).getAddress()), opaque);
      const state = position(100n, 40n, opaque);
      for (const hops of [[], [target]]) {
        const expected = exactInput
          ? encodePositionBlock(hops.at(-1) ?? asset, 100n, liability, 40n, opaque)
          : encodePositionBlock(asset, 100n, hops.at(-1) ?? liability, 40n, opaque);
        expect(await opaqueHost[method].staticCall(encodeContextBlock(account, state, route(...hops))))
          .deep.eq([expected, 0n]);
      }
    });

    it(`${method} rejects unmatched positions, routes, malformed framing and unconsumed bytes atomically`, async () => {
      const validRoute = route(target);
      const validAsset = encodeAssetBlock(target);
      const cases: [string, string, string][] = [
        [position(), "0x", "InvalidBlock"], ["0x", route(), "InvalidBlock"],
        [position(), concat(validRoute, route()), "InvalidBlock"],
        [concat(position(), position()), validRoute, "InvalidBlock"],
        [encodeBlock(Keys.Position, "0x"), validRoute, "InvalidBlock"],
        [encodeBlock(Keys.Position, concat(ethers.dataSlice(position(), 8), pad32(1n))), validRoute, "InvalidBlock"],
        [encodeSwapBlock(asset, 100n), validRoute, "InvalidBlock"],
        [position().slice(0, -2), validRoute, "OutOfBounds"],
        [position(), validRoute.slice(0, -2), "OutOfBounds"],
        [position(), encodeBytesBlock(validAsset), "InvalidBlock"],
        [position(), encodeSwapBlock(asset, 100n, target), "InvalidBlock"],
        [position(), validRoute + "ff", "InvalidBlock"],
        [position() + "ff", validRoute, "InvalidBlock"],
      ];
      for (const [bad, error] of [
        [encodeBlock(Keys.Node, target), "InvalidBlock"],
        [encodeBlock(Keys.Asset, "0x"), "InvalidBlock"],
        [encodeBlock(Keys.Asset, concat(target, target)), "InvalidBlock"],
        [encodeListBlock(validAsset), "InvalidBlock"],
        ["0xff", "InvalidBlock"],
        [validAsset.slice(0, -2), "OutOfBounds"],
      ]) {
        cases.push([position(), encodeListBlock(bad), error]);
        cases.push([position(), encodeListBlock(concat(validAsset, bad)), error]);
      }
      for (const [state, input, error] of cases) {
        for (const context of [encodeContextBlock(account, state, input),
          encodeContextBlock(account, concat(position(), state), concat(validRoute, input))]) {
          await expect(host[method](context, { gasLimit: 3_000_000 })).revertedWithCustomError(host, error);
          expect(await host.calls()).eq(0n);
        }
      }
      const context = encodeContextBlock(account, position(), validRoute);
      for (const bad of ["0x", concat(context, "0xff"), concat(context, context)]) {
        await expect(host[method](bad)).revertedWithCustomError(host, "InvalidBlock");
      }
    });

    it(`${method} propagates hook rejection and rolls back earlier hops and positions`, async () => {
      for (const rejectAt of [1n, 2n, 3n]) {
        await host.configure(3n, rejectAt);
        const context = encodeContextBlock(account, concat(position(), position()), concat(route(middle, target), route(target)));
        await expect(host[method](context, { gasLimit: 3_000_000 })).revertedWithCustomError(host, "HookRejected");
        expect(await host.calls()).eq(0n);
      }
    });
  }

  for (const source of ["swapExactInput", "swapExactOutput"]) {
    it(`composes both transforms over a ${source} batch using the same hooks`, async () => {
      await host.configure(3n, 0n);
      const input = concat(encodeSwapBlock(asset, 100n, middle), encodeSwapBlock(liability, 200n, target));
      const [initial] = await host[source].staticCall(encodeContextBlock(account, "0x", input));
      const assetRoutes = concat(route(target), route(middle, asset));
      const debtRoutes = concat(route(liability, asset), route(middle));
      const [assetOutput] = await host.swapAssetExactInput.staticCall(encodeContextBlock(account, initial, assetRoutes));
      const [combined] = await host.swapDebtExactOutput.staticCall(encodeContextBlock(account, assetOutput, debtRoutes));
      const expected = source === "swapExactInput"
        ? concat(encodePositionBlock(target, 94n, asset, 106n, counterparty), encodePositionBlock(asset, 191n, middle, 203n, counterparty))
        : concat(encodePositionBlock(target, 97n, asset, 109n, counterparty), encodePositionBlock(asset, 194n, middle, 206n, counterparty));
      expect(combined).eq(expected);
      const [debtOutput] = await host.swapDebtExactOutput.staticCall(encodeContextBlock(account, initial, debtRoutes));
      expect(await host.swapAssetExactInput.staticCall(encodeContextBlock(account, debtOutput, assetRoutes)))
        .deep.eq([expected, 0n]);
    });
  }
});
