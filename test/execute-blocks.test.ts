import { expect } from "chai";
import { ethers } from "ethers";
import { deploy } from "./helpers/setup.js";
import { Keys } from "./helpers/blocks.js";
import { executeCases, executeStreams, block } from "./helpers/execute-blocks.js";
import "./helpers/matchers.js";

async function failure(call: Promise<unknown>) {
  try { await call; } catch (error: any) { return error.data ?? error.info?.error?.data; }
  throw new Error("Expected revert");
}

describe("Execute", () => {
  it("allocates exact balance output and rejects sizes beyond the encoded limit", async () => {
    const helper = await deploy("TestExecuteBlocks");
    for (const count of [0, 1, 2, 4]) {
      const expected = ethers.concat(Array.from({ length: count }, (_, i) => block(Keys.Balance, [i + 1, ethers.MaxUint256 - BigInt(i)])));
      expect(await helper.balanceOutput(count)).eq(expected);
    }
    for (const count of [0xffffffffn / 72n + 1n, 0xffffffffn]) {
      await expect(helper.balanceOutput(count)).revertedWithCustomError(helper, "ValueOverflow");
    }
  });

  it("keeps decoded positions independent of the source and each other", async () => {
    const helper = await deploy("TestExecuteBlocks");
    const fields = [ethers.MaxUint256, ethers.MaxUint256, 2n, ethers.MaxUint256, 9n];
    const source = ethers.concat([block(Keys.Position, fields), block(Keys.Position, fields)]);
    const r = await helper.inspectPositions(source);
    expect(Array.from(r.first)).deep.eq([ethers.toBeHex(fields[0], 32), 0n, ethers.toBeHex(2, 32), ethers.MaxUint256, ethers.toBeHex(99, 32)]);
    expect(Array.from(r.second)).deep.eq([ethers.toBeHex(fields[0], 32), fields[1], ethers.toBeHex(2, 32), fields[3], ethers.toBeHex(9, 32)]);
    expect(r.beforeHash).eq(ethers.keccak256(source));
    expect(r.afterHash).eq(r.beforeHash);
    expect(r.allocated).eq(320n);
  });

  it("validates the selected fixed-stride range once and ignores cursor metadata", async () => {
    const helper = await deploy("TestExecuteBlocks");
    const source = "0x" + "ab".repeat(200);
    for (const metadata of [0n, ethers.MaxUint256]) {
      for (const [start, end] of [[1, 1], [7, 79], [3, 147]]) {
        expect(Array.from(await helper.bounds(source, start, end, metadata, 72))).deep.eq([BigInt(start), BigInt(end - start)]);
      }
      await expect(helper.bounds(source, 3, 146, metadata, 72)).revertedWithCustomError(helper, "InvalidBlock");
    }
  });

  it("preserves output, state, funding and empty-stream behavior in adapters with unchanged input schemas", async () => {
    const before = await deploy("ExecuteAdaptersBaseline");
    const after = await deploy("ExecuteAdaptersCurrent");
    const native = BigInt(await after.nativeAsset());
    for (const name of executeCases) {
      // Composite Bootstrap behavior is covered in bootstrap.test.ts.
      if (name === "Bootstrap") continue;
      for (const count of [0, 1, 4]) {
        const [state, input] = executeStreams(name, count, native);
        const a = await before["measure" + name].staticCall(state, input, 100);
        const b = await after["measure" + name].staticCall(state, input, 100);
        expect(Array.from(b).slice(1), name).deep.eq(Array.from(a).slice(1));
        expect(b.stateHash).eq(ethers.keccak256(state));
      }
    }
  });

  it("preserves exact failures for partial streams, bad headers, and hook precedence", async () => {
    const before = await deploy("ExecuteAdaptersBaseline");
    const after = await deploy("ExecuteAdaptersCurrent");
    const native = BigInt(await after.nativeAsset());
    for (const name of executeCases) {
      // Composite Bootstrap behavior is covered in bootstrap.test.ts.
      if (name === "Bootstrap") continue;
      const [state, input] = executeStreams(name, 2, native);
      const memory = state !== "0x";
      const stream = memory ? state : input;
      const partial = ethers.dataSlice(stream, 0, ethers.dataLength(stream) - 1);
      const wrongKey = ethers.concat(["0xffffffff", ethers.dataSlice(stream, 4)]);
      const wrongLength = ethers.concat([ethers.dataSlice(stream, 0, 4), "0xffffffff", ethers.dataSlice(stream, 8)]);
      const cases = [[memory ? partial : state, memory ? input : partial],
        [memory ? wrongKey : state, memory ? input : wrongKey],
        [memory ? wrongLength : state, memory ? input : wrongLength],
        [state, ethers.concat([input, "0x01"])]];
      if (!memory) cases.push(["0x01", input]);
      for (const [s, i] of cases) {
        const a = await failure(before["measure" + name].staticCall(s, i, 100));
        const b = await failure(after["measure" + name].staticCall(s, i, 100));
        expect(b, name).eq(a);
      }
    }
    const invalidBlock = ethers.id("InvalidBlock()").slice(0, 10);
    for (const [name, key, fields, memory] of [
      ["DebitAccount", Keys.AssetAmount, [native, ethers.MaxUint256], false],
      ["CreditAccount", Keys.Balance, [native, ethers.MaxUint256], true],
      ["Settle", Keys.Position, [native, ethers.MaxUint256, 2n, 3n, 9n], true],
    ] as const) {
      const stream = ethers.concat([block(key, [...fields]), "0x01"]);
      // Upfront divisibility must beat the first hook's deliberate revert.
      expect(await failure(after["measure" + name].staticCall(memory ? stream : "0x", memory ? "0x" : stream, 100))).eq(invalidBlock);
    }
    expect(await after.checksum()).eq(0n);
  });
});
