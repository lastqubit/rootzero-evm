import { ethers } from "ethers";
import type { RawLog } from "./log-blocks.js";
// Category 6 is reserved for the removed Pipeline event.
export const Category = { Access: 1, Introduction: 2, Metadata: 3, Execution: 4, Endpoint: 5, Balance: 7, Envelope: 8, Resolution: 9 } as const;
export const word = (value: bigint | number | string) => ethers.toBeHex(value, 32);
export const eventRecord = (category: number, ...fields: string[]) => ethers.concat([ethers.toBeHex(category, 1), ...fields]);
export const executionRecord = (id: bigint, account: string, ...blocks: string[]) => eventRecord(Category.Execution, word(id), account, ...blocks);
export const balanceRecord = (account: string, asset: string, balance: bigint) => eventRecord(Category.Balance, account, asset, word(balance));
export function categoryPayload(log: RawLog, category: number, size?: number): string | null {
  if (log.topics.length || ethers.dataLength(log.data) === 0 || Number(ethers.dataSlice(log.data, 0, 1)) !== category) return null;
  const payload = ethers.dataSlice(log.data, 1);
  if (size !== undefined && ethers.dataLength(payload) !== size) throw new Error("Invalid category record length");
  return payload;
}
