import { expect } from "chai";
import { ethers } from "ethers";
import { fixture, checkScenario } from "./helpers/bootstrap-short.js";
import { concat, encodeAssetAmountBlock, encodeBootstrapBlock, encodeBlock, Keys } from "./helpers/blocks.js";
import "./helpers/matchers.js";

const invalid = ethers.id("InvalidBlock()").slice(0, 10);
async function outcome(call: Promise<any>) {
  try { const r = await call; return { output: r[0], credit: r[1] }; }
  catch (error: any) { if (typeof error.data !== "string") throw error; return { error: error.data }; }
}

describe("Bootstrap shared allocation compatibility", function () {
  this.timeout(240_000);
  it("preserves output, logs, funding and hook counts with dirty memory and allocating hooks", async () => {
    const f = await fixture();
    for (const host of f.hosts) await (await host.setAllocate(true)).wait();
    for (const count of [0, 1, 2, 3, 4, 5, 8, 15, 32, 128]) for (const kind of ["native", "other", "first", "last", "mixed"]) {
      const requests: [string, bigint][] = Array.from({ length: count }, (_, i) => [
        kind === "native" || (kind === "first" && i === 0) || (kind === "last" && i === count - 1) || (kind === "mixed" && i % 2 === 0)
          ? f.native : f.tokens[i % 4], BigInt(i % 3)]);
      for (const value of [0n, 300n]) await checkScenario(f, { name: `dirty/${count}/${kind}/${value}`, count, requests, budget: 9n, value, zeros: "mixed" });
    }
  });

  it("matches the frozen decoder and funding errors across the reference malformed corpus", async () => {
    const f = await fixture(), other = f.tokens[0];
    const cases: { input: string; value: bigint; malformed?: boolean }[] = [];
    const make = (requests: [string, bigint][], budget = 0n) => encodeBootstrapBlock(budget, concat(...requests.map(([a, n]) => encodeAssetAmountBlock(a, n))));
    for (const asset of [f.native, other]) for (const amount of [0n, 1n, 13n, 101n]) for (const budget of [0n, 9n]) for (const value of [0n, 7n, 30n]) cases.push({ input: make([[asset, amount]], budget), value });
    for (const requests of [[], [[f.native, 0n]], [[f.native, 3n], [other, 0n], [f.native, 4n]], [[other, 3n], [f.native, 4n], [other, 2n]], [[f.native, ethers.MaxUint256], [f.native, 1n]], [[f.native, ethers.MaxUint256]]] as [string, bigint][][])
      cases.push({ input: make(requests, 1n), value: 0n });
    const valid = cases[0].input;
    for (let length = 0; length < ethers.dataLength(valid); length += 7) cases.push({ input: ethers.dataSlice(valid, 0, length), value: 0n, malformed: true });
    cases.push({ input: concat(valid, "0x00"), value: 0n, malformed: true }, { input: encodeBlock(Keys.Bytes, ethers.dataSlice(valid, 8)), value: 0n, malformed: true });
    const corrupt = (input: string, offset: number, value: bigint) => {
      const bytes = ethers.getBytes(input); bytes[offset] ^= 0xff;
      cases.push({ input: ethers.hexlify(bytes), value, malformed: true });
    };
    for (const offset of [0, 4, 40, 44, 48, 52]) corrupt(valid, offset, 0n);
    let seed = 139039;
    const random = (max: number) => { seed = (Math.imul(seed, 1664525) + 1013904223) >>> 0; return seed % max; };
    for (let i = 0; i < 128; i++) {
      const requests: [string, bigint][] = Array.from({ length: random(5) }, () => [random(2) ? f.native : other, BigInt(random(40))]);
      const value = BigInt(random(25)), budget = BigInt(random(20));
      cases.push({ input: make(requests, budget), value });
    }
    for (const assets of [[other, other, other], [f.native, other, other], [other, other, f.native]]) {
      const input = make(assets.map(a => [a, 1n]));
      for (let item = 0; item < 3; item++) for (const field of [0, 4]) corrupt(input, 48 + item * 72 + field, 0n);
    }
    for (let count = 1; count <= 4; count++) for (let mask = 0; mask < 1 << count; mask++) {
      const input = make(Array.from({ length: count }, (_, i) => [mask & (1 << i) ? f.native : other, 1n]), 9n);
      for (let item = 0; item < count; item++) for (const field of [0, 4]) corrupt(input, 48 + item * 72 + field, 3n);
    }
    for (const count of [5, 8, 15]) for (const kind of ["native", "other", "mixed"]) cases.push({ input: make(Array.from({ length: count }, (_, i) => [kind === "native" || (kind === "mixed" && i % 2 === 0) ? f.native : other, BigInt(i % 3)]), 9n), value: 3n });
    expect(cases.length).eq(431);
    for (const [i, c] of cases.entries()) {
      const results = await Promise.all(f.hosts.map(host => outcome(host.probe.staticCall(c.input, "0x", 0, ethers.dataLength(c.input), c.value))));
      expect(results[1], `zero/${i}`).deep.eq(results[0]); expect(results[2], `current/${i}`).deep.eq(results[0]);
      if (c.malformed) expect(results[2], `malformed/${i}`).deep.eq({ error: invalid });
    }
    for (const host of f.hosts) {
      expect(await outcome(host.probe.staticCall(valid, "0x", 1, 0, 0))).deep.eq({ error: invalid });
      expect(await outcome(host.probe.staticCall(concat(valid, valid), "0x", 0, ethers.dataLength(valid) - 1, 0))).deep.eq({ error: invalid });
      await expect(host.probe(valid, "0x01", 0, ethers.dataLength(valid), 0)).revertedWithCustomError(host, "UnexpectedState");
      await (await host.seed(f.account, [f.native], ethers.MaxUint256)).wait();
      const maximum = make([[f.native, ethers.MaxUint256]], ethers.MaxUint256);
      expect((await host.probe.staticCall(maximum, "0x", 0, ethers.dataLength(maximum), ethers.MaxUint256))[1]).eq(ethers.MaxUint256);
    }
  });

  it("rolls back earlier hooks on malformed later blocks, native overflow and insufficient funds", async () => {
    const f = await fixture();
    const ordinary = encodeAssetAmountBlock(f.tokens[0], 3n);
    for (const host of f.hosts) for (const [tail, error] of [
      [encodeBlock(Keys.Balance, concat(f.native, ethers.toBeHex(1, 32))), invalid],
      [concat(encodeAssetAmountBlock(f.native, ethers.MaxUint256), encodeAssetAmountBlock(f.native, 1n)), concat("0x4e487b71", ethers.toBeHex(0x11, 32))],
      [encodeAssetAmountBlock(f.native, 1001n), ethers.id("InsufficientFunds()").slice(0, 10)],
    ]) {
      const input = encodeBootstrapBlock(0n, concat(ordinary, tail));
      expect(await outcome(host.probe.staticCall(input, "0x", 0, ethers.dataLength(input), 0))).deep.eq({ error });
      let failed = false;
      try { await (await host.run(input, { gasLimit: 2_000_000 })).wait(); } catch { failed = true; }
      expect(failed).eq(true);
      expect(await host.balanceOf(f.account, f.tokens[0])).eq(1000n);
      expect(await host.balanceOf(f.account, f.native)).eq(1000n);
      expect(await host.hookCalls()).eq(0n);
      expect(await f.provider.getBalance(await host.getAddress())).eq(1000n);
    }
  });
});
