import { expect } from "chai";
import { ethers } from "ethers";
import { mkdirSync, writeFileSync } from "node:fs";
import { deploy } from "./helpers/setup.js";

const abi = ethers.AbiCoder.defaultAbiCoder();
const payload = (size: number) => ethers.hexlify(Uint8Array.from({ length: size }, (_, j) => (j * 17 + 5) % 256));
async function outcome(call: () => Promise<any>) {
  try { const r = await call(); return { first: r.first, output: r.output }; }
  catch (error: any) {
    const data = error.data ?? error.info?.error?.data;
    if (typeof data !== "string") throw error;
    return { error: data };
  }
}

// Adapt frozen bytes-only return fixtures to the current call tuple ABI.
const withCredit = (data: string) => ethers.dataLength(data) < 32 ? data : ethers.concat([
  ethers.toBeHex((BigInt(ethers.dataSlice(data, 0, 32)) + 32n) & ethers.MaxUint256, 32),
  ethers.ZeroHash, ethers.dataSlice(data, 32),
]);

describe("Calls and Specs optimization", function () {
  this.timeout(120_000);

  it("compares tuple calls and bytes queries with the frozen bytes-only baseline", async () => {
    const helper = await deploy("TestCallsSpecsOptimization");
    const target = await deploy("TestRawReturndata");
    const rows: any[] = [];
    for (const mode of [0, 1, 2]) {
      for (const count of [1, 8]) {
        for (const size of [0, 1, 2, 31, 32, 33, 256, 4096]) {
          const output = payload(size);
          const input = abi.encode(["bytes"], [output]);
          const cfg = { mode, count, target: await target.getAddress(),
            selector: target.interface.getFunction("returnRaw")!.selector, expectEmpty: size === 0 };
          const before = await helper.measure.staticCall(false, cfg, input);
          const after = await helper.measure.staticCall(true, cfg, mode === 2 || cfg.selector === target.interface.getFunction("revertRaw")!.selector ? input : withCredit(input));
          expect(after.output).to.equal(output);
          expect(after.first).to.equal(output);
          expect(after.output).to.equal(before.output);
          expect(after.first).to.equal(before.first);
          expect(before.footprint - after.footprint).to.equal((mode === 2 ? 32n : 0n) * BigInt(count));
          if (mode === 2) expect(after.usedGas).to.be.lessThan(before.usedGas);
          rows.push({ mode, count, size, before: Number(before.usedGas), after: Number(after.usedGas),
            saved: Number(before.usedGas - after.usedGas) });
        }
      }
    }
    mkdirSync(".npm-cache", { recursive: true });
    writeFileSync(".npm-cache/calls-layout-results.json", JSON.stringify(rows, null, 2) + "\n");
    console.table(rows.filter(r => r.count === 1));
  });

  it("preserves malformed returns, dirty padding, and exact failure data while tightening expectEmpty", async () => {
    const helper = await deploy("TestCallsSpecsOptimization");
    const target = await deploy("TestRawReturndata");
    const valid = abi.encode(["bytes"], ["0x1234"]);
    const cases = ["0x", ...[1, 31, 32, 63].map(payload), valid,
      ethers.concat([abi.encode(["uint", "uint"], [0, 0])]),
      abi.encode(["uint", "uint"], [32, ethers.MaxUint256]),
      abi.encode(["uint", "uint"], [32, ethers.MaxUint256 - 31n]),
      abi.encode(["uint", "uint"], [32, 1]), valid + "00",
      valid.slice(0, -2), valid.slice(0, -2) + "ff",
      ...[0, 1, 2, 3, 31, 32, 33, 64].map(n => abi.encode(["bytes"], [payload(n)]))];
    const failed = new ethers.Interface(["error FailedCall(address addr, bytes4 selector, bytes err)"]);
    for (const mode of [0, 1, 2]) {
      for (const expectEmpty of [false, true]) {
        for (const method of ["returnRaw", "revertRaw"]) {
          const cfg = { mode, count: 1, target: await target.getAddress(),
            selector: target.interface.getFunction(method)!.selector, expectEmpty };
          for (const input of cases) {
            const before = await outcome(() => helper.measure.staticCall(false, cfg, input));
            const after = await outcome(() => helper.measure.staticCall(true, cfg, mode === 2 || cfg.selector === target.interface.getFunction("revertRaw")!.selector ? input : withCredit(input)));
            // The frozen baseline accepted even nonzero lengths with expectEmpty.
            const expected = mode !== 2 && expectEmpty && before.output !== undefined && before.output !== "0x"
              ? { error: "0x" } : before;
            expect(after).to.deep.equal(expected);
            if (method === "revertRaw") expect(after).to.deep.equal({ error:
              failed.encodeErrorResult("FailedCall", [cfg.target, cfg.selector, input]) });
          }
        }
      }
    }
  });

  it("requires zero output length when expectEmpty is set for both memory and calldata calls", async () => {
    const helper = await deploy("TestCallsSpecsOptimization");
    const target = await deploy("TestRawReturndata");
    for (const mode of [0, 1]) {
      for (const size of [0, 1, 2, 3, 31, 32, 33, 64, 256]) {
        const output = payload(size);
        const input = abi.encode(["bytes"], [output]);
        for (const expectEmpty of [false, true]) {
          const cfg = { mode, count: 1, target: await target.getAddress(),
            selector: target.interface.getFunction("returnRaw")!.selector, expectEmpty };
          const result = await outcome(() => helper.measure.staticCall(true, cfg, mode === 2 || cfg.selector === target.interface.getFunction("revertRaw")!.selector ? input : withCredit(input)));
          expect(result).to.deep.equal(expectEmpty && size > 0
            ? { error: "0x" } : { first: output, output });
        }
      }
    }
  });

  it("forwards native value unchanged", async () => {
    const helper = await deploy("TestCallsSpecsOptimization");
    const target = await deploy("TestRawReturndata");
    for (const mode of [0, 1]) {
      const cfg = { mode, count: 1, target: await target.getAddress(),
        selector: target.interface.getFunction("returnValue")!.selector, expectEmpty: false };
      for (const optimized of [false, true]) {
        const callCfg = { ...cfg, selector: target.interface.getFunction(optimized ? "returnValueCredit" : "returnValue")!.selector };
        const r = await helper.measure.staticCall(optimized, callCfg, "0x", { value: 123 });
        expect(r.output).to.equal(abi.encode(["uint"], [123]));
      }
    }
  });

  it("benchmarks size hints and preserves allocation overflow", async () => {
    const helper = await deploy("TestCallsSpecsOptimization");
    const rows: any[] = [];
    for (const allocation of [false, true]) {
      for (const key of [0n, 1n, 0xffffffffn]) {
        for (const hint of [0n, 1n, 128n, 0xffffffn]) {
          const spec = (key << 224n) | (hint << 136n) | ((1n << 136n) - 1n);
          for (const repeats of [1, 8]) {
            const before = await helper.specSize(false, allocation, spec, 17, repeats);
            const after = await helper.specSize(true, allocation, spec, 17, repeats);
            expect(after.result).to.equal((key === 0n ? 0n : 8n + hint) * (allocation ? 17n : 1n));
            expect(after.result).to.equal(before.result);
            if (key !== 0n) expect(after.usedGas).to.be.lessThan(before.usedGas);
            rows.push({ allocation, key: String(key), hint: String(hint), repeats,
              saved: Number(before.usedGas - after.usedGas) });
          }
          if (allocation && key !== 0n) {
            const maxCount = ethers.MaxUint256 / (8n + hint);
            for (const optimized of [false, true]) {
              expect((await helper.specSize(optimized, true, spec, maxCount, 1)).result)
                .to.equal(maxCount * (8n + hint));
              expect(await outcome(() => helper.specSize(optimized, true, spec, maxCount + 1n, 1)))
                .to.deep.equal({ error: "0x4e487b71" + abi.encode(["uint"], [0x11]).slice(2) });
            }
          }
        }
      }
    }
    console.table(rows.filter(r => r.repeats === 1 && r.hint === "128"));
    writeFileSync(".npm-cache/specs-size-results.json", JSON.stringify(rows, null, 2) + "\n");
  });

  it("measures failure-path gas separately", async () => {
    const helper = await deploy("TestCallsSpecsOptimization");
    const target = await deploy("TestRawReturndata");
    const rows: any[] = [];
    for (const mode of [0, 1, 2]) {
      for (const size of [0, 1, 32, 33, 256, 4096]) {
        const cfg = { mode, count: 1, target: await target.getAddress(),
          selector: target.interface.getFunction("revertRaw")!.selector, expectEmpty: false };
        const before = await helper.probeFailure.staticCall(false, cfg, payload(size));
        const after = await helper.probeFailure.staticCall(true, cfg, payload(size));
        expect(after.errorData).to.equal(before.errorData);
        rows.push({ mode, size, saved: Number(before.usedGas - after.usedGas) });
      }
    }
    console.table(rows);
    writeFileSync(".npm-cache/calls-failure-results.json", JSON.stringify(rows, null, 2) + "\n");
  });
});
