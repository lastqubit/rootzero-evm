import { encodeBalanceBlock, encodeBalanceConstraintsBlock, concat, pad32 } from "./blocks.js";

export const layoutModes = ["input", "state", "mixed", "deferred"] as const;
export function layoutFixture(mode: number, count: number, seed = 17n) {
  const balances: string[] = [], constraints: string[] = [];
  let checksum = 2n * seed + 7n + BigInt(count);
  for (let i = 0; i < count; ++i) {
    const asset = BigInt(i + 1), amount = BigInt(i + 10);
    const checked = amount + (mode === 3 ? 1n : 0n);
    balances.push(encodeBalanceBlock(pad32(asset), amount));
    constraints.push(encodeBalanceConstraintsBlock(pad32(asset), checked, checked));
    checksum += asset + checked;
  }
  return {
    input: mode === 0 ? concat(...balances) : mode === 1 ? "0x" : concat(...constraints),
    state: mode === 0 ? "0x" : concat(...balances), checksum, seed,
  };
}
