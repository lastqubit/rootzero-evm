import { expect } from "chai";
import { ethers } from "ethers";
import { deploy } from "./helpers/setup.js";
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
