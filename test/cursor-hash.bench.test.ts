import { expect } from "chai";
import hre from "hardhat";
import { ethers } from "ethers";
import { deploy } from "./helpers/setup.js";

describe("Cursor hash optimization", () => {
  it("inlines length to identical runtime bytecode", async () => {
    const current = await hre.artifacts.readArtifact("CursorLengthCurrent");
    const baseline = await hre.artifacts.readArtifact("CursorLengthBaseline");
    const executable = (code: string) => code.slice(0, -(parseInt(code.slice(-4), 16) + 2) * 2);
    expect(executable(current.deployedBytecode)).eq(executable(baseline.deployedBytecode));
  });

  it("compares scratch hashing with keccak256(toBytes(cur)) under viaIR", async () => {
    const current = await deploy("CursorHashCurrent");
    const baseline = await deploy("CursorHashBaseline");
    const rows: { size: number; before: number; after: number; saved: number }[] = [];
    for (const size of [0, 1, 31, 32, 33, 64, 256, 1024, 4096]) {
      const source = ethers.hexlify(new Uint8Array(size + 1).fill(0xab));
      const before = await baseline.measure(source, 1, size + 1, ethers.MaxUint256);
      const after = await current.measure(source, 1, size + 1, ethers.MaxUint256);
      expect(after.digest).eq(before.digest);
      expect(after.usedGas).lte(before.usedGas);
      rows.push({ size, before: Number(before.usedGas), after: Number(after.usedGas), saved: Number(before.usedGas - after.usedGas) });
    }
    console.table(rows);
  });
});
