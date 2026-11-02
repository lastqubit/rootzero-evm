import { expect } from "chai";
import { ethers } from "ethers";
import { commandId, deploy, getSigner, hostId } from "./helpers/setup.js";
import {
  blockKey, concat, encodeBlock, encodeStringBlock, encodeUserAccount, endpointSpecs, exactSpec,
  rangedSpec, Keys, Variants, withVariant,
} from "./helpers/blocks.js";
import "./helpers/matchers.js";

const position = exactSpec(Keys.Position, 160);
const amount = exactSpec(Keys.Amount, 32);
const names = ["debt", "counterparty", "ledger", "same", "realized", "repaid", "keepDebt", "keepAsset"];
const variants = [
  Variants.Debt, Variants.Counterparty, Variants.Ledger, Variants.Same,
  Variants.Realized, Variants.Repaid, Variants.KeepDebt, Variants.KeepAsset,
];

describe("Lane variants", () => {
  let helper: Awaited<ReturnType<typeof deploy>>;
  before(async () => { helper = await deploy("TestLaneVariants"); });

  it("derives keys from scoped names and packs the POSITION variant constants into bits 63-32", async () => {
    expect(variants).deep.eq(names.map(name => blockKey(`position.${name}`)));
    expect(variants).deep.eq([
      "0x43713627", "0x2841eda5", "0x40a08141", "0x60649c75", "0x3b6cdd34", "0x9a4d821c", "0x1901fefb", "0xf83a2669",
    ]);
    expect(Array.from(await helper.keys())).deep.eq(variants);
    const specs = Array.from(await helper.specs()) as bigint[];
    expect(specs).deep.eq(variants.map(v => withVariant(position, v)));
    for (const [i, spec] of specs.entries()) {
      expect(await helper.variant(spec)).eq(variants[i]);
      expect(await helper.toVariant(position, variants[i])).eq(spec);
      expect(spec >> 64n).eq(position >> 64n);
      expect(spec & 0xffffffffn).eq(0n);
    }
    const [plain, counterparty] = await helper.plain();
    expect(plain).eq(position);
    expect(counterparty).eq(exactSpec(Keys.Counterparty, 32));
    expect(Array.from(await helper.barrels())).deep.eq([Variants.Debt, Variants.KeepAsset, specs[7]]);
  });

  it("reads the variant independently of the lane key and reports zero without one", async () => {
    expect(await helper.variant(position)).eq("0x00000000");
    expect(await helper.variant(position | 0xffffffffn)).eq("0x00000000");
    expect(await helper.variant(0n)).eq("0x00000000");
    expect(await helper.variant(withVariant(position, "0xffffffff") | 7n)).eq("0xffffffff");
  });

  it("packs any nonzero variant while preserving block fields and the lane key", async () => {
    for (const spec of [position, amount, rangedSpec(Keys.List, 0, 0, 128), amount | 0xffffffffn]) {
      for (const variant of ["0x00000001", "0xffffffff", Variants.Ledger]) {
        expect(await helper.toVariant(spec, variant)).eq(withVariant(spec, variant));
      }
    }
  });

  it("rejects an empty spec, a zero variant, an existing variant and reserved bits", async () => {
    const cases: [bigint, string][] = [
      [0n, Variants.Debt],
      [0xffffffffn, Variants.Debt],
      [position, "0x00000000"],
      [withVariant(position, Variants.Debt), Variants.Debt],
      [withVariant(position, Variants.Debt), Variants.Ledger],
      [position | (1n << 32n), Variants.Debt],
      [position | (1n << 63n), Variants.Debt],
      [position | (1n << 64n), Variants.Debt],
      [position | (1n << 100n), Variants.Debt],
      [position | (1n << 135n), Variants.Debt],
    ];
    for (const [spec, variant] of cases) {
      await expect(helper.toVariant(spec, variant)).revertedWithCustomError(helper, "InvalidSpec");
    }
  });

  it("composes toLane and toVariant in either order", async () => {
    for (const variant of variants) {
      for (const laneKey of [1n, 0xffffffffn]) {
        const expected = withVariant(position, variant) | laneKey;
        expect(await helper.laneThenVariant(position, laneKey, variant)).eq(expected);
        expect(await helper.variantThenLane(position, variant, laneKey)).eq(expected);
        expect(await helper.toLane(withVariant(position, variant), laneKey)).eq(expected);
      }
    }
  });

  it("keeps toLane rejecting zero keys, existing lane keys, EMPTY and bits 135-64", async () => {
    const cases: [bigint, bigint][] = [
      [position, 0n],
      [0n, 1n],
      [withVariant(0n, Variants.Debt), 1n],
      [position | 2n, 1n],
      [withVariant(position, Variants.Debt) | 2n, 1n],
      [position | (1n << 64n), 1n],
      [position | (1n << 135n), 1n],
    ];
    for (const [spec, laneKey] of cases) {
      await expect(helper.toLane(spec, laneKey)).revertedWithCustomError(helper, "InvalidSpec");
    }
  });

  it("describes lanes with variants exactly like plain lanes and still rejects bits 135-64", async () => {
    const lanes: [bigint, bigint, bigint][] = [[0n, amount, position], [position, amount, position], [position, 0n, 0n]];
    for (const [state, input, output] of lanes) {
      const plain = await helper.describe(state, input, output);
      const vary = (spec: bigint, variant: string) => spec === 0n ? 0n : withVariant(spec, variant) | 9n;
      expect(await helper.describe(vary(state, Variants.Counterparty), vary(input, "0xffffffff"),
        vary(output, Variants.Same))).eq(plain);
    }
    for (const bit of [64n, 100n, 127n, 128n, 135n]) {
      for (const index of [0, 1, 2]) {
        const specs: [bigint, bigint, bigint] = [position, amount, withVariant(position, Variants.Same)];
        specs[index] |= 1n << bit;
        await expect(helper.describe(...specs)).revertedWithCustomError(helper, "InvalidSpec");
      }
    }
  });
});

describe("Lane variants in endpoint records", () => {
  const counterparty = encodeUserAccount(ethers.toBeHex(5, 20));

  it("publishes the inline POSITION variants of position-transforming commands", async () => {
    const swaps = await deploy("TestSwapCommands", await hostId(await (await getSigner()).getAddress()), counterparty);
    const list = rangedSpec(Keys.List, 0, 0, 128);
    for (const [method, output] of [["swapAssetExactInput", Variants.KeepDebt], ["swapDebtExactOutput", Variants.KeepAsset]]) {
      await expect(swaps.deploymentTransaction()).to.emitEndpoint(swaps).withArgs(await commandId(`${method}(bytes)`, swaps),
        withVariant(position, Variants.Counterparty), list, withVariant(position, output), method);
    }
    for (const method of ["swapExactInput", "swapExactOutput"]) {
      await expect(swaps.deploymentTransaction()).to.emitEndpoint(swaps).withArgs(await commandId(`${method}(bytes)`, swaps),
        ...endpointSpecs({ input: Keys.Swap, inputHint: 256, output: position }), method);
    }

    const realize = await deploy("TestRealize");
    await expect(realize.deploymentTransaction()).to.emitEndpoint(realize).withArgs(
      await commandId("realize(bytes)", realize),
      withVariant(position, Variants.Counterparty), 0n, withVariant(position, Variants.Realized), "realize");

    const check = await deploy("TestCheckPosition");
    await expect(check.deploymentTransaction()).to.emitEndpoint(check).withArgs(await check.commandId(),
      position, exactSpec(Keys.PositionConstraints, 128), withVariant(position, Variants.Same), "checkPosition");

    const repay = await deploy("TestRepayCommand");
    await expect(repay.deploymentTransaction()).to.emitEndpoint(repay).withArgs(await commandId("repay(bytes)", repay),
      position, 0n, withVariant(position, Variants.Repaid), "repay");
  });

  it("publishes a host's settleState() override without changing the endpoint ID", async () => {
    const plain = await deploy("TestSettleCommand");
    await expect(plain.deploymentTransaction()).to.emitEndpoint(plain)
      .withArgs(await plain.commandId(), position, 0n, 0n, "settle");

    const host = await deploy("TestSettleStateVariant");
    const id = await host.commandId();
    expect(id).eq(await commandId("settle(bytes)", host));
    await expect(host.deploymentTransaction()).to.emitEndpoint(host)
      .withArgs(id, withVariant(position, Variants.Counterparty), 0n, 0n, "settle");
  });

  it("publishes swap output hook overrides without changing the endpoint IDs", async () => {
    const commander = await hostId(await (await getSigner()).getAddress());
    const host = await deploy("TestSwapOutputVariant", commander, counterparty);
    for (const method of ["swapExactInput", "swapExactOutput"]) {
      const [state, input] = endpointSpecs({ input: Keys.Swap, inputHint: 256 });
      await expect(host.deploymentTransaction()).to.emitEndpoint(host).withArgs(await commandId(`${method}(bytes)`, host),
        state, input, withVariant(position, Variants.Counterparty), method);
    }
  });

  it("adds a variant to an inherited described lane while keeping its lane key and description", async () => {
    const commander = await hostId(await (await getSigner()).getAddress());
    const host = await deploy("TestPoolInputVariant", commander);
    const variant: string = await host.VARIANT();
    expect(variant).eq(blockKey("assetAmount.test"));
    const described = exactSpec(Keys.AssetAmount, 64) | BigInt(blockKey("addPool"));
    await expect(host.deploymentTransaction()).to.emitEndpoint(host).withArgs(
      await commandId("addPool(bytes)", host, 2n), 0n, withVariant(described, variant), 0n, "addPool");
    // lane(...) publishes its description before the override adds the variant.
    await expect(host.deploymentTransaction()).to.emitMetadata(host).withArgs(await host.host(),
      encodeBlock(blockKey("#lane"), concat(ethers.toBeHex(described, 32), encodeStringBlock("#assetAmount[2] as (a, b)"))));
    // removePool keeps its default hook.
    const removed = exactSpec(Keys.Asset, 32) | BigInt(blockKey("removePool"));
    await expect(host.deploymentTransaction()).to.emitEndpoint(host).withArgs(
      await commandId("removePool(bytes)", host, 2n), 0n, removed, 0n, "removePool");
  });
});
