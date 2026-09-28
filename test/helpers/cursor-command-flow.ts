import { concat, encodeBalanceBlock, encodePositionConstraintsBlock, encodeStepBlock, pad32 } from "./blocks.js";

// Different values per record/command catch skipped, repeated, and stale cursors.
export function commandFlow(steps: number, children: number) {
  const blocks: string[] = [];
  let sum = 0n;
  for (let i = 0; i < steps; ++i) {
    const cmd = BigInt(i % 2 + 1), value = BigInt(i + 11);
    const records: string[] = [];
    sum += value;
    for (let j = 0; j < children; ++j) {
      const asset = BigInt(i + j + 1), amount = BigInt(i + j + 7);
      const other = BigInt(j + 91), otherAmount = BigInt(j + 3);
      records.push(concat(
        encodeBalanceBlock(pad32(asset), amount),
        encodePositionConstraintsBlock(pad32(asset), amount, pad32(2n), 3n),
        encodeBalanceBlock(pad32(other), otherAmount),
      ));
      sum += asset + other + (cmd === 1n ? amount + otherAmount : amount * otherAmount);
    }
    blocks.push(encodeStepBlock(cmd, value, concat(...records)));
  }
  return { source: concat(...blocks), sum, records: BigInt(steps * children) };
}
