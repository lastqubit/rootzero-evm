import { expect } from "chai";
import hre from "hardhat";
import { deploy } from "./helpers/setup.js";
import "./helpers/matchers.js";

function executable(code: string) {
  return code.slice(0, -(parseInt(code.slice(-4), 16) + 2) * 2);
}

describe("Cursor done helper", () => {
  it("compiles the command-style guard to identical executable bytecode", async () => {
    const a = executable((await hre.artifacts.readArtifact("CursorDoneGuardDirect")).deployedBytecode);
    const b = executable((await hre.artifacts.readArtifact("CursorDoneGuardShared")).deployedBytecode);
    expect(b).eq(a);
  });
  it("compares the direct check's behavior, gas, and executable bytecode", async () => {
    const direct = await deploy("CursorDoneDirect"), shared = await deploy("CursorDoneShared");
    const a = executable((await hre.artifacts.readArtifact("CursorDoneDirect")).deployedBytecode);
    const b = executable((await hre.artifacts.readArtifact("CursorDoneShared")).deployedBytecode);
    // gasleft instrumentation can move calldata loading across the measured boundary.
    // Keep this diagnostic separate from the identical uninstrumented guard above.
    const rows: any[] = [];
    for (const [abs, end] of [[0n, 0n], [9n, 9n], [0xffffffffn, 0xffffffffn], [0n, 1n], [8n, 9n], [9n, 8n]]) {
      const cur = abs | (end << 32n);
      expect(await shared.done(cur)).eq(abs === end);
      expect(await shared.done(cur)).eq(await direct.done(cur));
      if (abs === end) {
        const before = await direct.measure(cur), after = await shared.measure(cur);
        rows.push({ abs: Number(abs), direct: Number(before), shared: Number(after), delta: Number(after - before),
          directTransaction: Number(await direct.measure.estimateGas(cur)), sharedTransaction: Number(await shared.measure.estimateGas(cur)) });
      }
      else for (const helper of [direct, shared]) {
        await expect(helper.measure(cur)).revertedWithCustomError(helper, "UnexpectedInput");
      }
    }
    console.log({ identicalExecutable: a === b });
    console.table(rows);
  });
});
