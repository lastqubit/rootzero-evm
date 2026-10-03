import { expect } from "chai";
import { readFile } from "node:fs/promises";

describe("Code catalog invariants", () => {
  it("keeps every uint identifier unique and inside its assigned 32-bit category", async () => {
    const seen = new Set<bigint>();
    for (const [catalog, category] of [["Actions", 0n], ["Entities", 1n], ["Effects", 4n], ["States", 5n]] as const) {
      const source = await readFile(new URL(`../contracts/utils/${catalog}.sol`, import.meta.url), "utf8");
      const entries = [...source.matchAll(/^\s*(uint(?:\d+)?)\s+constant\s+(\w+)\s*=\s*([^;]+);/gm)];
      expect(entries.length, catalog).greaterThan(0);
      for (const [, type, name, literal] of entries) {
        const label = `${catalog}.${name}`;
        const value = BigInt(literal.trim());
        expect(type, label).eq("uint");
        expect(value >= 0n && value <= 0xffffffffn, `${label} width`).eq(true);
        expect(value >> 29n, `${label} category`).eq(category);
        expect(seen.has(value), `${label} duplicate`).eq(false);
        expect(value === 0n, `${label} zero sentinel`).eq(catalog === "Actions" && name === "None");
        seen.add(value);
      }
    }
  });
});
