import { expect } from "chai";
import { ethers } from "ethers";
import { mkdirSync, writeFileSync } from "node:fs";
import hre from "hardhat";
import { deploy } from "./helpers/setup.js";
import { encodeContextBlock, encodeStateBlock, encodeInputBlock } from "./helpers/blocks.js";

describe("Encoder boolean representation benchmark", function () {
  this.timeout(180_000);

  it("compares explicit helpers, literal flags, and runtime flags for all child combinations", async () => {
    const runtime = await deploy("TestEncoderFlagsRuntime");
    const rows: any[] = [];
    const account = ethers.toBeHex(7n, 32);
    for (let mode = 0; mode < 4; ++mode) {
      const baseline = await deploy(`TestEncoderFlagsBaseline${mode}`);
      const literal = await deploy(`TestEncoderFlagsLiteral${mode}`);
      const stateBlock = (mode & 2) !== 0, inputBlock = (mode & 1) !== 0;
      for (const [a, b] of [[0, 0], [1, 1], [24, 25], [257, 2048]]) {
        const state = "0x" + "ab".repeat(a), input = "0x" + "cd".repeat(b);
        const expected = encodeContextBlock(account, state, input);
        const stateSource = stateBlock ? encodeStateBlock(state) : state;
        const inputSource = inputBlock ? encodeInputBlock(input) : input;
        for (const memory of [false, true]) for (const writer of [false, true]) for (const count of [1, 16]) {
          const args = [account, stateSource, inputSource, stateBlock, inputBlock, memory, writer, count];
          const results: number[] = [];
          for (const helper of [baseline, literal, runtime]) {
            const result = await helper.measure(...args);
            const size = ethers.dataLength(expected);
            expect(writer ? ethers.dataSlice(result[2], 3, 3 + size) : result[2]).eq(expected);
            if (writer) {
              expect(ethers.dataSlice(result[2], 0, 3)).eq("0xefefef");
              expect(ethers.dataSlice(result[2], 3 + size + 24)).eq("0x" + "ef".repeat(32));
              if (stateBlock && inputBlock) {
                expect(ethers.dataSlice(result[2], 3 + size)).eq("0x" + "ef".repeat(56));
              }
              expect(result[1]).eq(0n);
            } else {
              expect(result[1]).eq(BigInt(count * (64 + Math.ceil(size / 32) * 32)));
            }
            results.push(Number(result[0]));
          }
          rows.push({ mode, memory, writer, stateSize: a, inputSize: b, count,
            baseline: results[0], literal: results[1], runtime: results[2],
            literalDelta: results[1] - results[0], runtimeDelta: results[2] - results[0] });
        }
      }
    }
    console.table(rows.filter(r => r.count === 16 && r.stateSize === 1));
    mkdirSync(".npm-cache", { recursive: true });
    writeFileSync(".npm-cache/block-encoder-flags-results.json", JSON.stringify({
      compiler: hre.config.solidity.profiles.default.compilers[0], rows,
    }, null, 2) + "\n");
  });
});
