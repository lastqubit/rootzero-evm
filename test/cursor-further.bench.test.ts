import { expect } from "chai";
import { mkdirSync, writeFileSync } from "node:fs";
import hre from "hardhat";
import { deploy } from "./helpers/setup.js";
import { concat } from "./helpers/blocks.js";
import { consumerKinds, size, consumerBlock, expectedConsumer } from "./helpers/cursor-consumers.js";

describe("Further cursor optimization comparisons", function () {
  this.timeout(120_000);
  it("compares cursor operations, bounds checks, and absolute child loops", async () => {
    const rows: any[] = [];
    for (const kind of consumerKinds) for (const variant of ["New", "PackedLT", "Clean", "Repack", "ReadFirst", "Signed", ...(kind !== "Chain" ? ["Hybrid", "HybridNext"] : []), ...(kind === "Envelope" ? ["Bytes", "BytesPackedLT", "EnterNow", "AdvanceFirst", "ChildReturns", "BytesComposed", "BytesHybrid"] : [])]) {
      const old = await deploy(`CursorConsumer${kind}Old`), current = await deploy(`CursorConsumer${kind}${variant}`);
      const oldArtifact = await hre.artifacts.readArtifact(`CursorConsumer${kind}Old`);
      const newArtifact = await hre.artifacts.readArtifact(`CursorConsumer${kind}${variant}`);
      for (const children of kind === "Chain" ? [1] : [0, 1, 4, 16]) for (const count of [1, 32, 128]) {
        const source = concat(...Array(count).fill(consumerBlock(kind, children)));
        const a = await old.measure(source, size(source), 0, 0xa5n << 64n);
        const b = await current.measure(source, size(source), 0, 0xa5n << 64n);
        const expected = expectedConsumer(kind, children, count);
        for (const r of [a, b]) {
          expect(r[1]).eq(expected.sum); expect(r[2]).eq(expected.count);
          const end = r[4] + BigInt(size(source));
          expect(r[3]).eq(end | (end << 32n) | (0xa5n << 64n));
        }
        expect(b[3]).eq(a[3]);
        rows.push({ kind, variant, children, count, old: Number(a[0]), current: Number(b[0]),
          oldBytes: (oldArtifact.deployedBytecode.length - 2) / 2, currentBytes: (newArtifact.deployedBytecode.length - 2) / 2 });
      }
    }
    const slopes = rows.filter(r => r.count === 128).map(r => {
      const match = (s: any) => s.kind === r.kind && s.variant === r.variant && s.children === r.children;
      const one = rows.find(s => match(s) && s.count === 1), middle = rows.find(s => match(s) && s.count === 32);
      const old = (r.old - one.old) / 127, current = (r.current - one.current) / 127;
      expect((r.old - middle.old) / 96).eq(old);
      expect((r.current - middle.current) / 96).eq(current);
      return { kind: r.kind, variant: r.variant, children: r.children, old, current, delta: current - old, oldBytes: r.oldBytes, currentBytes: r.currentBytes };
    });
    console.table(slopes.filter(r => r.children === 4 || r.kind === "Chain"));
    mkdirSync(".npm-cache", { recursive: true });
    writeFileSync(".npm-cache/cursor-further-results.json", JSON.stringify({ compiler: hre.config.solidity.profiles.default.compilers[0], rows, slopes }, null, 2) + "\n");
  });
});
