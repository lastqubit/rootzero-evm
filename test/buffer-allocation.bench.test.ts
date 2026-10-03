import { expect } from "chai";
import { ethers } from "ethers";
import { mkdirSync, writeFileSync } from "node:fs";
import { deploy } from "./helpers/setup.js";
import { concat, encodeAssetAmountBlock, encodeBalanceBlock, encodeBytesBlock, encodePositionBlock } from "./helpers/blocks.js";

describe("Buffer allocation benchmark", () => {
  it("compares scanning, lazy growth, and byte-length hints with identical output", async () => {
    const helper = await deploy("TestBufferAllocation");
    const asset = ethers.toBeHex(1n, 32);
    const liability = ethers.toBeHex(2n, 32);
    const workloads = ["equal", "expanding", "shrinking", "variable", "sparse", "unused", "underestimate", "overestimate", "zero_hint"];
    const strategies = ["scan", "lazy", "bytes1x", "bytes2x", "bytes4x", "divisible", "ceiling", "production"];
    const results: object[] = [];
    for (let workload = 0; workload < workloads.length; ++workload) {
      for (const count of [0, 1, 8, 17, 64, 256]) {
        const inputs: string[] = [];
        const outputs: string[] = [];
        for (let i = 0; i < count; ++i) {
          const amount = workload === 8 ? 128 : workload === 6 ? 0 : workload === 7 ? 264 : workload === 2 ? 256 : workload === 3 ? [0, 16, 256, 2048][i % 4]! : i + 1;
          inputs.push(workload === 2 || workload === 3 || workload >= 6
            ? encodeBytesBlock("0x" + "a5".repeat(amount)) : encodeAssetAmountBlock(asset, BigInt(amount)));
          if (workload === 1) outputs.push(encodePositionBlock(asset, BigInt(amount), liability, BigInt(amount)));
          else if (workload !== 5 && (workload !== 4 || i % 8 === 0)) outputs.push(encodeBalanceBlock(asset, BigInt(amount)));
        }
        const input = concat(...inputs);
        const output = concat(...outputs);
        for (const repetitions of count === 64 ? [1, 8, 32] : [1]) {
          for (let strategy = 0; strategy < strategies.length; ++strategy) {
            if (repetitions === 32 && ![0, 5, 6, 7].includes(strategy)) continue;
            const [gas, memory, length, digest] = await helper.measure(strategy, workload, input, repetitions, { gasLimit: 16_000_000 });
            expect(length).to.equal(BigInt(ethers.dataLength(output)));
            expect(digest).to.equal(ethers.keccak256(output));
            results.push({ workload: workloads[workload], count, repetitions, strategy: strategies[strategy],
              inputBytes: ethers.dataLength(input), outputBytes: ethers.dataLength(output), gas: Number(gas), memory: Number(memory) });
          }
        }
      }
    }
    mkdirSync(".npm-cache", { recursive: true });
    writeFileSync(".npm-cache/buffer-allocation-results.json", JSON.stringify(results, null, 2) + "\n");
    console.log(`        ${results.length} measurements; results in .npm-cache/buffer-allocation-results.json`);
  });
});
