import { expect } from "chai";
import { ethers } from "ethers";
import { mkdirSync, writeFileSync } from "node:fs";
import hre from "hardhat";
import { deploy } from "./helpers/setup.js";
import { concat, encodeBlock, Keys } from "./helpers/blocks.js";

describe("Uniform unpacker consuming loops", function () {
  this.timeout(120_000);
  it("measures direct use of every unpacker's returned stream cursor", async () => {
    const rows: any[] = [];
    for (const kind of ["64", "160", "Balance", "Step", "Relay", "Context"]) {
      const helper = await deploy(`CursorUniform${kind}`);
      const key = kind === "64" || kind === "160" ? "0xdeadbeef" : Keys[kind as keyof typeof Keys];
      const values = kind === "160" ? [1, 2, 3, 4, 5] : kind === "Relay" ? [] : kind === "Context" ? [1] : [1, 2];
      const children = ["64", "160", "Balance"].includes(kind) ? [] : kind === "Step" ? ["0x" + "ab".repeat(33)] : ["0x", "0x" + "ab".repeat(33)];
      const childKeys = kind === "Step" ? [Keys.Input]
        : kind === "Relay" ? [Keys.Input, Keys.Bytes] : [Keys.State, Keys.Input];
      const block = encodeBlock(key, concat(...values.map(v => ethers.toBeHex(v, 32)), ...children.map((c, i) => encodeBlock(childKeys[i], c))));
      const checksum = BigInt(values.reduce((a, v) => a + v, 0) + children.reduce((a, c) => a + ethers.getBytes(c).length, 0));
      const artifact = await hre.artifacts.readArtifact(`CursorUniform${kind}`);
      for (const count of [1, 32, 128]) {
        const r = await helper.measure(concat(...Array(count).fill(block)), key);
        expect(r[1]).eq(checksum * BigInt(count));
        expect(r[2] >> 64n).eq(0xa5n);
        expect(r[2] & 0xffffffffn).eq((r[2] >> 32n) & 0xffffffffn);
        rows.push({ kind, count, gas: Number(r[0]), runtimeBytes: (artifact.deployedBytecode.length - 2) / 2 });
      }
    }
    const slopes = rows.filter(r => r.count === 128).map(r => {
      const one = rows.find(s => s.kind === r.kind && s.count === 1);
      const middle = rows.find(s => s.kind === r.kind && s.count === 32);
      const perBlock = (r.gas - one.gas) / 127;
      expect((r.gas - middle.gas) / 96).eq(perBlock);
      return { kind: r.kind, perBlock, runtimeBytes: r.runtimeBytes };
    });
    console.table(slopes);
    mkdirSync(".npm-cache", { recursive: true });
    writeFileSync(".npm-cache/cursor-uniform-results.json", JSON.stringify({ compiler: hre.config.solidity.profiles.default.compilers[0], rows, slopes }, null, 2) + "\n");
  });
});
