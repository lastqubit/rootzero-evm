import { expect } from "chai";
import { ethers } from "ethers";
import { deploy } from "./helpers/setup.js";
import { concat, encodeBalanceBlock, encodePositionConstraintsBlock, encodeStepBlock, pad32 } from "./helpers/blocks.js";
import { size } from "./helpers/cursor-consumers.js";
import { commandFlow } from "./helpers/cursor-command-flow.js";

describe("Packed cursor command flow", function () {
  this.timeout(120_000);
  for (const variant of ["Old", "New"]) describe(variant, () => {
    let helper: any;
    before(async () => { helper = await deploy(`CursorCommandFlow${variant}`); });
    it("chains all records and commands and preserves the enclosing range and metadata", async () => {
      for (const steps of [0, 1, 3]) for (const children of [0, 1, 4]) {
        const fixture = commandFlow(steps, children);
        const source = concat("0x123456", fixture.source, commandFlow(1, 1).source);
        const length = 3 + size(fixture.source);
        for (const metadata of [0n, 0xa5n << 64n, ethers.MaxUint256]) {
          const r = await helper.measure(source, length, 3, metadata);
          expect(r[1]).eq(fixture.sum); expect(r[2]).eq(fixture.records);
          const end = r[4] + BigInt(length);
          expect(r[3]).eq(end | (end << 32n) | (metadata & ~((1n << 64n) - 1n)));
        }
      }
    });
    async function rejects(source: string, length = size(source)) {
      let data: unknown;
      try { await helper.measure(source, length, 0, 0); }
      catch (e: any) { data = e.data ?? e.info?.error?.data; }
      expect(data).to.be.a("string");
    }
    it("rejects a shortened logical stream despite physical trailing calldata", async () => {
      const { source } = commandFlow(2, 2);
      for (const length of [1, 7, 8, size(source) - 1]) await rejects(source, length);
    });
    it("checks each chained field and does not read across the command input boundary", async () => {
      const balance = encodeBalanceBlock(pad32(1n), 7n);
      const constraints = encodePositionConstraintsBlock(pad32(1n), 7n, pad32(2n), 3n);
      const badConstraints = encodePositionConstraintsBlock(pad32(1n), 8n, pad32(2n), 3n);
      for (const body of [balance, concat(balance, constraints), concat(balance, badConstraints, balance),
        concat(balance, constraints, ethers.dataSlice(balance, 0, 71)), concat(balance, balance, balance),
        concat(balance, constraints, balance, "0xff")]) {
        const step = encodeStepBlock(1n, 0n, body);
        await rejects(concat(step, commandFlow(1, 1).source));
      }
      await rejects(encodeStepBlock(99n, 0n, "0x"));
    });
  });
});
