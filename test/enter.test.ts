import { expect } from "chai";
import { ethers } from "ethers";
import { deploy } from "./helpers/setup.js";
import "./helpers/matchers.js";
import { concat, encodeBlock, exactSpec, Keys } from "./helpers/blocks.js";

for (const kind of ["Execution", "Decoder"]) {
describe(`${kind} enter optimization`, () => {
  let current: Awaited<ReturnType<typeof deploy>>;
  let baseline: Awaited<ReturnType<typeof deploy>>;
  const spec = exactSpec(Keys.Bytes, 208);
  const parent = encodeBlock(Keys.Bytes, "0x" + "11".repeat(208));
  before(async () => {
    current = await deploy(kind === "Execution" ? "TestEnterCurrent" : "TestDecoderEnterCurrent");
    baseline = await deploy(kind === "Execution" ? "TestEnterBaseline" : "TestDecoderEnterBaseline");
  });
  async function outcome(host: typeof current, input: string, expected: bigint, amount: bigint, mode: number) {
    try { return Array.from(await host.enterOnce(input, expected, amount, mode)); }
    catch (error: any) { return error.data ?? error.info?.error?.data; }
  }
  for (const mode of [0, 1, 2, 3]) {
    it(`preserves results, errors and cursor metadata for overload ${mode}`, async () => {
      const cases: [string, bigint, bigint][] = [
        [parent, spec, 0n], [parent, spec, 104n], [parent, spec, 208n],
        [parent, spec, 209n], [parent, spec, ethers.MaxUint256],
        [parent, exactSpec(Keys.String, 208), 0n], [parent, exactSpec(Keys.Bytes, 207), 0n],
        ["0x", spec, 0n], [ethers.dataSlice(parent, 0, 7), spec, 0n],
        [ethers.dataSlice(parent, 0, 8), spec, 0n], [ethers.dataSlice(parent, 0, 8), spec, 1n],
        [ethers.dataSlice(parent, 0, 112), spec, 104n], [ethers.dataSlice(parent, 0, 112), spec, 105n],
        [encodeBlock(Keys.Bytes, "0x"), exactSpec(Keys.Bytes, 0), 0n],
      ];
      for (const [input, expected, amount] of cases) {
        const old = await outcome(baseline, input, expected, amount, mode);
        expect(old).not.to.equal(undefined);
        expect(await outcome(current, input, expected, amount, mode)).to.deep.equal(old);
      }
      expect(Array.from(await current.enterOnce(parent, spec, 104n, mode)))
        .to.deep.equal([8n, 216n, mode < 2 ? 8n : 112n, true]);
    });
    it(`measures overload ${mode} across 32 fixed-size parents`, async () => {
      const input = concat(...Array(32).fill(parent));
      const [oldGas, oldResult] = await baseline.measure(input, spec, 104n, mode);
      const [newGas, newResult] = await current.measure(input, spec, 104n, mode);
      expect(newResult).to.equal(oldResult);
      console.log(`${kind} enter mode=${mode}: baseline=${oldGas}, optimized=${newGas}, saved/parent=${(BigInt(oldGas) - BigInt(newGas)) / 32n}`);
    });
  }
});

}


describe("Execution descend", () => {
  let helper: Awaited<ReturnType<typeof deploy>>;
  const child = encodeBlock(Keys.Bytes, "0x010203");
  const parent = encodeBlock(Keys.List, concat(child, encodeBlock(Keys.String, "0xaa")));
  const parentSpec = exactSpec(Keys.List, 20);
  const childSpec = exactSpec(Keys.Bytes, 3);
  before(async () => { helper = await deploy("TestEnterCurrent"); });

  it("returns child and parent bounds and preserves every non-position bit", async () => {
    expect(await helper.descendOnce(parent, parentSpec, childSpec, 28, ethers.MaxUint256))
      .to.deep.equal([16n, 19n, 28n, 16n, true]);
  });

  it("allows empty children and leaves payload-end checks to the caller", async () => {
    const empty = encodeBlock(Keys.List, encodeBlock(Keys.Bytes, "0x"));
    expect(await helper.descendOnce(empty, exactSpec(Keys.List, 8), exactSpec(Keys.Bytes, 0), 16, 0))
      .to.deep.equal([16n, 16n, 16n, 16n, true]);
    // Both headers fit, but the child payload extends beyond the parent and input.
    const headers = encodeBlock(Keys.List, ethers.dataSlice(child, 0, 8));
    expect(await helper.descendOnce(headers, exactSpec(Keys.List, 8), childSpec, 16, 0))
      .to.deep.equal([16n, 19n, 16n, 16n, true]);
  });

  it("rejects a child payload start beyond the input limit", async () => {
    for (const limit of [0, 7, 8, 15]) {
      await expect(helper.descendOnce(parent, parentSpec, childSpec, limit, 0))
        .to.be.revertedWithCustomError(helper, "OutOfBounds");
    }
  });

  it("validates both specifications before checking the cursor bound", async () => {
    for (const [p, c] of [
      [exactSpec(Keys.Bytes, 20), childSpec],
      [exactSpec(Keys.List, 21), childSpec],
      [parentSpec, exactSpec(Keys.String, 3)],
      [parentSpec, exactSpec(Keys.Bytes, 2)],
    ]) {
      await expect(helper.descendOnce(parent, p, c, 0, 0))
        .to.be.revertedWithCustomError(helper, "InvalidBlock");
    }
  });
});
