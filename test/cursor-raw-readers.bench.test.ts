import { expect } from "chai";
import hre from "hardhat";
import { deploy } from "./helpers/setup.js";

describe("CursorBlocks raw reader optimization", () => {
  it("compiles thin read32 casts to the same runtime as direct calldata loads", async () => {
    const current = await hre.artifacts.readArtifact("CursorRawReadersCurrent");
    const direct = await hre.artifacts.readArtifact("CursorRawReadersDirect");
    const executable = (code: string) => code.slice(0, -(parseInt(code.slice(-4), 16) + 2) * 2);
    expect(executable(current.deployedBytecode)).eq(executable(direct.deployedBytecode));
    const helper = await deploy("CursorRawReadersCurrent");
    const baseline = await deploy("CursorRawReadersDirect");
    for (const width of [1, 2, 4, 8, 16, 32]) {
      const method = "read" + width;
      expect(await helper[method].estimateGas(0)).eq(await baseline[method].estimateGas(0));
    }
  });
});
