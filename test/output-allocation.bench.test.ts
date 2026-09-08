import { expect } from "chai";
import { ethers } from "ethers";
import { mkdirSync, writeFileSync } from "node:fs";
import { deploy } from "./helpers/setup.js";
import { concat, encodeBalanceBlock, encodePositionBlock, encodeBytesBlock } from "./helpers/blocks.js";

describe("Output-only allocation benchmark", () => {
  it("compares zero and one-block hints with identical output", async () => {
    const helper = await deploy("TestOutputAllocation");
    const asset = ethers.toBeHex(1, 32);
    const liability = ethers.toBeHex(2, 32);
    const workloads = ["balance", "position", "bytes16", "bytes128", "bytes1024"];
    const results: object[] = [];
    for (let workload = 0; workload < workloads.length; ++workload) {
      for (const count of [0, 1, 2, 3, 4, 8, 64, 256]) {
        const expected = concat(...Array.from({ length: count }, (_, i) =>
          workload === 0 ? encodeBalanceBlock(asset, BigInt(i + 1))
            : workload === 1 ? encodePositionBlock(asset, BigInt(i + 1), liability, BigInt(i + 1))
              : encodeBytesBlock("0x" + "00".repeat(workload === 2 ? 16 : workload === 3 ? 128 : 1024))));
        for (const repetitions of count === 8 ? [1, 16] : [1]) {
          for (const seed of [false, true]) {
            const [gas, memory, length, digest] = await helper.measure(seed, workload, count, repetitions,
              { gasLimit: 16_000_000 });
            expect(length).to.equal(BigInt(ethers.dataLength(expected)));
            expect(digest).to.equal(ethers.keccak256(expected));
            results.push({ workload: workloads[workload], count, repetitions,
              strategy: seed ? "one_block" : "zero", gas: Number(gas), memory: Number(memory) });
          }
        }
      }
    }
    mkdirSync(".npm-cache", { recursive: true });
    writeFileSync(".npm-cache/output-allocation-results.json", JSON.stringify(results, null, 2) + "\n");
    console.log(`        ${results.length} measurements`);
  });
});
