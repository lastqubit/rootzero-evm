import { expect } from "chai";
import hre from "hardhat";
import { ethers } from "ethers";
import { mkdirSync, writeFileSync } from "node:fs";
import { deploy } from "./helpers/setup.js";
import { Keys, encodeBlock, concat } from "./helpers/blocks.js";
import "./helpers/matchers.js";

function executable(code: string) {
  const metadataBytes = parseInt(code.slice(-4), 16);
  return code.slice(0, -(metadataBytes + 2) * 2);
}

describe("Named unpackers composed from word primitives", function () {
  this.timeout(120_000);
  it("compares identical cursor consumers, including constant keys and next-cursor chaining", async () => {
    const rows: any[] = [];
    const codeRows: any[] = [];
    for (const [name, words] of [["AssetAmount", 2], ["Balance", 2], ["Position", 5]] as const) {
      const directName = `Unpack${name}Direct`, composedName = `Unpack${name}Composed`;
      const direct = await deploy(directName), composed = await deploy(composedName);
      const current = name === "Balance" ? await deploy("UnpackBalanceCurrent") : undefined;
      const aCode = executable((await hre.artifacts.readArtifact(directName)).deployedBytecode);
      const bCode = executable((await hre.artifacts.readArtifact(composedName)).deployedBytecode);
      codeRows.push({ name, identicalExecutable: aCode === bCode, directBytes: (aCode.length - 2) / 2, composedBytes: (bCode.length - 2) / 2 });
      const fields = Array.from({ length: words }, (_, i) => ethers.toBeHex((1n << 128n) + BigInt(i), 32));
      const block = encodeBlock(Keys[name], concat(...fields));
      for (const count of [1, 4, 16, 128]) {
        const source = concat(...Array(count).fill(block));
        const size = ethers.dataLength(source);
        const a = await direct.measure(source, size), b = await composed.measure(source, size);
        const sum = fields.reduce((s, f) => s + BigInt(f), 0n) * BigInt(count);
        expect(a[1]).eq(sum); expect(b[1]).eq(sum);
        expect(b[2]).eq(a[2]); expect(b[2] >> 128n).eq(0xa5n);
        expect(b[2] & 0xffffffffn).eq((b[2] >> 32n) & 0xffffffffn);
        if (current) expect(Array.from(await current.measure(source, size))).deep.eq(Array.from(a));
        rows.push({ name, count, direct: Number(a[0]), composed: Number(b[0]), delta: Number(b[0] - a[0]) });
      }
      for (const target of [direct, composed]) {
        for (const length of [1, 7, ethers.dataLength(block) - 1]) {
          await expect(target.measure(block, length)).to.be.revertedWithCustomError(target, "OutOfBounds");
        }
        const bad = concat("0x12345678", ethers.dataSlice(block, 4));
        await expect(target.measure(bad, ethers.dataLength(bad))).to.be.revertedWithCustomError(target, "InvalidBlock");
      }
    }
    console.table(rows);
    console.table(codeRows);
    mkdirSync(".npm-cache", { recursive: true });
    writeFileSync(".npm-cache/unpack-composition-results.json", JSON.stringify({ compiler: hre.config.solidity.profiles.default.compilers[0], rows, codeRows }, null, 2) + "\n");
  });
});
