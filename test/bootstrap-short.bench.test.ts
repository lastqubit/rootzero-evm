import { expect } from "chai";
import { ethers } from "ethers";
import { writeFileSync } from "node:fs";
import { fixture, scenarios, checkScenario, names, Scenario } from "./helpers/bootstrap-short.js";

describe("Bootstrap short shared allocation matrix", function () {
  this.timeout(900_000);
  it("compares stock, zero-inclusive reference and frozen v1.51 with exact outcomes", async () => {
    const f = await fixture(true);
    const matrix = scenarios(f.native, f.tokens);
    expect(matrix.length).eq(642);
    const rows: any[] = [];
    const larger: Scenario[] = [];
    for (const count of [0, 5, 8, 15, 32, 128]) for (const kind of ["native", "other", "mixed"]) {
      larger.push({ name: `${count}/${kind}`, count, zeros: "larger", budget: 9n, value: 3n,
        requests: Array.from({ length: count }, (_, i) => [kind === "native" || (kind === "mixed" && i % 2 === 0) ? f.native : f.tokens[i % 4], BigInt(i % 3)]) });
    }
    for (const s of [...matrix, ...larger]) {
      const [stock, zero, current] = await checkScenario(f, s);
      rows.push({ name: s.name, count: s.count, zeros: s.zeros, stock, zero, current,
        savedStock: stock.gas - current.gas, savedZero: zero.gas - current.gas });
    }
    const summary = [1, 2, 3, 4].map(count => {
      const sample = rows.filter(r => r.count === count && r.zeros !== "larger");
      const positive = sample.filter(r => r.zeros === "none" || r.zeros === "repeated");
      return { count, cases: sample.length, minimum: Math.min(...sample.map(r => r.savedZero)),
        maximum: Math.max(...sample.map(r => r.savedZero)), mean: sample.reduce((s, r) => s + r.savedZero, 0) / sample.length,
        regressions: sample.filter(r => r.savedZero < 0).length,
        stockPositiveMin: Math.min(...positive.map(r => r.savedStock)), stockPositiveMax: Math.max(...positive.map(r => r.savedStock)),
        stockRegressions: sample.filter(r => r.savedStock < 0).length, stockWorst: Math.min(...sample.map(r => r.savedStock)) };
    });
    const runtime = await Promise.all(f.hosts.map(async (host, i) => ({ name: i === 2 ? "BootstrapShortLogged151" : names[i], bytes: ethers.dataLength(await f.provider.getCode(await host.getAddress())) })));
    writeFileSync(".npm-cache/bootstrap-short-matrix.json", JSON.stringify({ compiler: "0.8.35", viaIR: true, optimizerRuns: 200, evmVersion: "cancun",
      scope: "Historical v1.51 logging policy. Identical ledger roundtrip harnesses; includes pipeline, Bootstrap, state and cashin logs; no token transfers. Zero hooks skipped in every variant.", runtime, summary, rows }, null, 2) + "\n");
    console.table(summary); console.table(runtime);
    console.table(rows.filter(r => r.zeros === "larger").map(({ name, savedStock, savedZero }) => ({ name, savedStock, savedZero })));
  });
});
