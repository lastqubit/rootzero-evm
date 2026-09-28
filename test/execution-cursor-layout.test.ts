import { expect } from "chai";
import { ethers } from "ethers";
import { deploy } from "./helpers/setup.js";
import { concat, encodeBalanceBlock, encodeBalanceConstraintsBlock, encodeBlock, Keys, pad32 } from "./helpers/blocks.js";
import { layoutFixture } from "./helpers/execution-cursor-layout.js";

describe("Execution cursor layout candidates", function () {
  for (const variant of ["Packed", "PackedPosition", "PackedDelta", "Split"]) describe(variant, () => {
    let helper: any;
    before(async () => { helper = await deploy(`ExecutionCursorLayout${variant}`); });
    it("matches independent results and preserves declared-lane flags", async () => {
      for (const mode of [0, 1, 2, 3]) for (const count of [0, 1, 3]) for (const flags of [0, 1, 2, 3]) {
        const f = layoutFixture(mode, count, 29n);
        const r = await helper.measure(f.input, f.state, mode, false, flags, f.seed);
        expect(r[1]).eq(f.checksum); expect(r[2]).eq(BigInt(count));
        expect(r[3] >> 64n).eq(BigInt(flags >> 1)); expect(r[4] >> 64n).eq(BigInt(flags & 1));
        for (const cur of [r[3], r[4]]) expect(cur & 0xffffffffn).eq((cur >> 32n) & 0xffffffffn);
      }
    });
    it("updates one lane without advancing the other", async () => {
      const block = encodeBalanceBlock(pad32(1n), 10n);
      for (const mode of [0, 1]) {
        const r = await helper.measure(block, block, mode, false, 3, 17);
        const untouched = mode === 0 ? r[4] : r[3];
        const consumed = mode === 0 ? r[3] : r[4];
        expect(((untouched >> 32n) & 0xffffffffn) - (untouched & 0xffffffffn)).eq(72n);
        expect(consumed & 0xffffffffn).eq((consumed >> 32n) & 0xffffffffn);
      }
    });
    it("rejects malformed blocks, leftover state, and failing deferred outcomes", async () => {
      const f = layoutFixture(2, 1), d = layoutFixture(3, 1);
      const wrong = encodeBlock(Keys.Bytes, "0x" + "00".repeat(64));
      for (const [input, state, mode, reason] of [
        [wrong, "0x", 0, "InvalidBlock()"], [ethers.dataSlice(f.state, 0, 71), "0x", 0, "OutOfBounds()"],
        [f.input, concat(f.state, "0xff"), 2, ""],
        [d.input, encodeBalanceBlock(pad32(1n), 20n), 3, "OutOfRange()"],
        [encodeBalanceConstraintsBlock(pad32(2n), 11n, 11n), d.state, 3, "UnexpectedValue()"],
      ] as const) {
        let error: unknown;
        try { await helper.measure(input, state, mode, false, 3, 17); }
        catch (e: any) { error = e.data ?? e.info?.error?.data; }
        expect(error).eq(reason ? ethers.id(reason).slice(0, 10) : "0x");
      }
    });
  });
});
