import { expect } from "chai";
import { ethers } from "ethers";
import { writeFile } from "node:fs/promises";
import { deploy } from "./helpers/setup.js";
import { concat, encodeBalanceBlock } from "./helpers/blocks.js";

describe("Single balance log composition", function () {
  this.timeout(180_000);
  it("compares allocated creation, temporary encoding, and output reuse with identical wire data", async () => {
    const asset = ethers.id("balance-log-asset");
    const rows: { variant: string; sample: string; count: number; helperGas: number;
      gasPerLog: number; retainedBytes: number; transactionGas: number }[] = [];
    for (const variant of ["Create", "Temporary", "TemporaryDirect", "Output", "Existing"]) {
      const helper = await deploy("BalanceLog" + variant);
      for (const [sample, amount, codes] of [
        ["zero", 0n, 0n], ["typical", 10n ** 18n, 80n],
        ["full-width", ethers.MaxUint256, ethers.MaxUint256],
      ] as const) for (const count of [1, 4, 16]) {
        const args = [codes, asset, amount, count] as const;
        const result = await helper.measure.staticCall(...args);
        const block = encodeBalanceBlock(asset, amount);
        expect(result.result).eq(variant === "Output" ? concat(...Array(count).fill(block))
          : variant === "Existing" ? block : "0x");
        expect(result.guard).eq(ethers.AbiCoder.defaultAbiCoder().encode(
          ["bytes32", "uint256"], [ethers.toBeHex(ethers.MaxUint256, 32), 0x1234]));
        expect(result.retainedBytes).eq(variant === "Create" ? BigInt(count * 128) : 0n);
        const receipt = await (await helper.measure(...args)).wait();
        expect(receipt.logs).to.have.length(count);
        for (const log of receipt.logs) {
          expect(log.topics).deep.eq([]);
          expect(log.data).eq(concat(ethers.toBeHex(codes, 32), block));
        }
        rows.push({ variant, sample, count, helperGas: Number(result.used),
          gasPerLog: Number(result.used) / count, retainedBytes: Number(result.retainedBytes),
          transactionGas: Number(receipt.gasUsed) });
      }
    }
    console.table(rows.filter(row => row.sample === "typical"));
    await writeFile("docs/benchmarks/BALANCE_LOG_COMPOSITION.json", JSON.stringify({
      compiler: "solc 0.8.35, viaIR, optimizer runs 200, Cancun",
      scope: "Timed loop includes block creation and logging except Existing, which measures only logging a previously written block. Output includes reservation and writing but initial writer allocation is outside timing. Temporary variants reserve 128 bytes across helper calls and restore the free-memory pointer. All logs contain the same 32-byte codes plus 72-byte Balance block. Excludes ABI decoding, guard construction, writer preparation, output finalization, and return encoding. Helper gas includes loop/timer overhead; transaction gas is not directly comparable because outputs differ.",
      rows,
    }, null, 2) + "\n");
  });
});
