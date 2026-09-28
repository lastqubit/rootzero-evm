import { expect } from "chai";
import { ethers } from "ethers";
import { deploy } from "./helpers/setup.js";
import { concat, encodeBlock, encodePositionConstraintsBlock, Keys } from "./helpers/blocks.js";
import { consumerKinds, size, balance, constraints, consumerBlock, expectedConsumer } from "./helpers/cursor-consumers.js";

async function rejected(call: Promise<any>) {
  try { await call; return false; }
  catch (e: any) { const data = e.data ?? e.info?.error?.data; if (typeof data !== "string") throw e; return true; }
}
describe("Complete absolute-position and cursor consumers", function () {
  this.timeout(120_000);
  for (const kind of consumerKinds) for (const variant of ["Old", "New", "PackedLT", "Clean", "Repack", "ReadFirst", "Signed", ...(kind !== "Chain" ? ["Hybrid", "HybridNext"] : []), ...(kind === "Envelope" ? ["Bytes", "BytesPackedLT", "EnterNow", "AdvanceFirst", "ChildReturns", "BytesComposed", "BytesHybrid"] : []), "AbsBalance", "AbsFixed", "AbsAll", "Cached", "Primitives", "Fused", "PrimitiveCached", "Compact", "Terminal", "FusedTerminal", ...(kind === "Chain" ? ["BalanceOnly", "ExpectOnly"] : ["Inline"]), ...(kind === "Envelope" ? ["Enter"] : [])]) describe(`${kind}/${variant}`, () => {
    let helper: any;
    before(async () => { helper = await deploy(`CursorConsumer${kind}${variant}`); });
    it("decodes equivalent results and preserves the stream end and metadata", async () => {
      for (const children of kind === "Chain" ? [1] : [0, 1, 4, 16]) for (const count of [0, 1, 3]) {
        const block = consumerBlock(kind, children), body = concat(...Array(count).fill(block));
        const source = concat("0x123456", body, block);
        for (const metadata of [0n, 0xa5n << 64n, ethers.MaxUint256]) {
          const length = 3 + size(body), r = await helper.measure(source, length, 3, metadata);
          const expected = expectedConsumer(kind, children, count);
          expect(r[1]).eq(expected.sum); expect(r[2]).eq(expected.count);
          const end = r[4] + BigInt(length);
          expect(r[3]).eq(end | (end << 32n) | (metadata & ~((1n << 64n) - 1n)));
        }
      }
    });
    it("rejects truncated logical ranges despite valid physical trailing bytes", async () => {
      const block = consumerBlock(kind, 2), source = concat(block, block);
      for (const length of [1, 7, 8, size(block) - 1]) {
        expect(await rejected(helper.measure(source, length, 0, 0))).eq(true);
      }
    });
    it("rejects malformed or out-of-bounds nested fields", async () => {
      const badBalance = encodeBlock(Keys.String, "0x");
      let cases: string[];
      if (kind === "Chain") {
        const badConstraints = encodeBlock(Keys.PositionConstraints, "0x");
        cases = [concat(badBalance, constraints), concat(balance, badConstraints), balance];
      } else {
        const bodies = [badBalance, ethers.dataSlice(balance, 0, size(balance) - 1), concat(balance, "0xff")];
        cases = bodies.map(body => kind === "Envelope" ? encodeBlock(Keys.Bytes, body)
          : encodeBlock(Keys.Step, concat(ethers.toBeHex(11, 32), ethers.toBeHex(13, 32), encodeBlock(Keys.Bytes, body))));
      }
      for (const source of cases) expect(await rejected(helper.measure(concat(source, balance), size(source), 0, 0))).eq(true);
    });
    if (kind === "Chain") it("preserves full-width constraint comparisons and identifier-before-quantity errors", async () => {
      const asset = ethers.toBeHex(1, 32), liability = ethers.toBeHex(2, 32), other = ethers.toBeHex(3, 32);
      for (const [minimum, maximum] of [[7n, 3n], [0n, ethers.MaxUint256], [0n, 1n << 128n]]) {
        const source = concat(balance, encodePositionConstraintsBlock(asset, minimum, liability, maximum));
        const r = await helper.measure(source, size(source), 0, ethers.MaxUint256);
        expect(r[1]).eq(8n); expect(r[2]).eq(1n);
      }
      for (const [a, minimum, l, maximum, reason] of [
        [other, ethers.MaxUint256, liability, 0n, "UnexpectedValue()"],
        [asset, ethers.MaxUint256, other, 0n, "UnexpectedValue()"],
        [asset, 8n, liability, 3n, "OutOfRange()"],
        [asset, 1n << 128n, liability, ethers.MaxUint256, "OutOfRange()"],
        [asset, 0n, liability, 0n, "OutOfRange()"],
      ] as const) {
        const source = concat(balance, encodePositionConstraintsBlock(a, minimum, l, maximum));
        let error: string | undefined;
        try { await helper.measure(source, size(source), 0, 0); }
        catch (e: any) { error = e.data ?? e.info?.error?.data; }
        expect(error).eq(ethers.id(reason).slice(0, 10));
      }
    });
  });
});
