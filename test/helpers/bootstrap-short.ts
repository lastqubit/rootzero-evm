import { expect } from "chai";
import { ethers } from "ethers";
import { deploy, getProvider, getSigner } from "./setup.js";
import { concat, encodeAssetAmountBlock, encodeBalanceBlock, encodeBootstrapBlock, encodePipelineBlock, encodeStateBlock } from "./blocks.js";

export type Request = [string, bigint];
export interface Scenario { name: string; count: number; zeros: string; budget: bigint; value: bigint; requests: Request[] }
export const initial = 1000n;
export const names = ["BootstrapShortStock", "BootstrapShortZero", "BootstrapShortCurrent"];
export const inputFor = (s: Scenario) => encodeBootstrapBlock(s.budget, concat(...s.requests.map(([a, n]) => encodeAssetAmountBlock(a, n))));
export const outputFor = (s: Scenario) => concat(...s.requests.map(([a, n]) => encodeBalanceBlock(a, n)));
const record = (prefix: bigint, data: string) => ({ topics: [], data: concat(ethers.toBeHex(prefix, 32), data) });

export function expected(s: Scenario, native: string, account: string, stock = false) {
  const total = s.requests.reduce((n, [a, q]) => n + (a === native ? q : 0n), 0n);
  const credit = s.value - total > s.budget ? s.value - total : s.budget;
  const debit = total + credit - s.value;
  const entries = s.requests.filter(([a, q]) => a !== native && (!stock || q !== 0n));
  if (debit) entries.push([native, debit]);
  const logs = [record(0x20000001n, encodePipelineBlock(account, s.value))];
  if (entries.length) logs.push(record((72n << 32n) | 0x20000001n, concat(...entries.map(([a, q]) => encodeBalanceBlock(a, q)))));
  logs.push(record(1n, encodeStateBlock(outputFor(s))));
  if (credit) logs.push(record((36n << 32n) | 0x20000001n, encodeBalanceBlock(native, credit)));
  const hooks = s.requests.filter(([a, q]) => a !== native && q !== 0n).length + (debit ? 1 : 0);
  return { credit, logs, hooks };
}

export function scenarios(native: string, tokens: string[]): Scenario[] {
  const result: Scenario[] = [];
  for (let count = 1; count <= 4; count++) for (let mask = 0; mask < 1 << count; mask++) {
    for (const zeros of ["none", "alternating", "all"]) for (const budget of [0n, 9n]) {
      const requests: Request[] = Array.from({ length: count }, (_, i) => [mask & (1 << i) ? native : tokens[i],
        zeros === "all" || (zeros === "alternating" && i % 2 === 0) ? 0n : BigInt(13 + 4 * i)]);
      const total = requests.reduce((sum, [a, q]) => sum + (a === native ? q : 0n), 0n);
      for (const value of new Set([0n, total / 2n, total + budget, total + budget + 7n]))
        result.push({ name: `${count}/${mask}/${zeros}/${budget}/${value}`, count, zeros, budget, value, requests });
    }
    for (const budget of [0n, 9n]) result.push({ name: `${count}/${mask}/repeated/${budget}/0`, count, zeros: "repeated", budget, value: 0n,
      requests: Array.from({ length: count }, (_, i) => [mask & (1 << i) ? native : tokens[0], BigInt(13 + 4 * i)]) });
  }
  return result;
}

export async function fixture() {
  const provider = await getProvider(), signer = await getSigner();
  const account = ethers.zeroPadValue(await signer.getAddress(), 32);
  const hosts = await Promise.all(names.map(name => deploy(name)));
  const native = await hosts[0].nativeAsset();
  const tokens = Array.from({ length: 4 }, (_, i) => ethers.id(`short-token-${i}`));
  for (const host of hosts) {
    await (await host.fund(account, { value: initial })).wait();
    await (await host.seed(account, tokens, initial)).wait();
  }
  return { provider, signer, account, hosts, native, tokens };
}

export async function checkScenario(f: Awaited<ReturnType<typeof fixture>>, s: Scenario) {
  const rows: { gas: number; executionGas: number }[] = [];
  for (const [index, host] of f.hosts.entries()) {
    const snapshot = await f.provider.send("evm_snapshot", []);
    try {
      const want = expected(s, f.native, f.account, index === 0);
      const result = await host.run.staticCall(inputFor(s), { value: s.value });
      expect(result[1], s.name).eq(outputFor(s));
      expect(result[2], s.name).eq(want.credit);
      const wallet = await f.provider.getBalance(await f.signer.getAddress());
      const receipt = await (await host.run(inputFor(s), { value: s.value })).wait();
      expect(receipt.logs.map((log: any) => ({ topics: [...log.topics], data: log.data })), s.name).deep.eq(want.logs);
      for (const a of [f.native, ...f.tokens]) expect(await host.balanceOf(f.account, a), s.name).eq(initial + (a === f.native ? s.value : 0n));
      expect(await host.hookCalls(), s.name).eq(BigInt(want.hooks));
      expect(await f.provider.getBalance(await host.getAddress()), s.name).eq(initial + s.value);
      expect(await f.provider.getBalance(await f.signer.getAddress()), s.name).eq(wallet - s.value - receipt.fee);
      rows.push({ gas: Number(receipt.gasUsed), executionGas: Number(result[0]) });
    } finally { await f.provider.send("evm_revert", [snapshot]); }
  }
  return rows;
}
