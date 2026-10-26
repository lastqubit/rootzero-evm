import { ethers } from "ethers";
import type { RawLog } from "./log-blocks.js";
// Pipeline, State, Input, Output and Value double as endpoint-ID flag bits.
export const Category = {
  Pipeline: 4, State: 8, Input: 16, Output: 32, Value: 64,
  Trust: 65, Introduction: 66, Metadata: 67, Endpoint: 68, Balance: 69, Envelope: 70, Resolution: 71,
} as const;
export const word = (value: bigint | number | string) => ethers.toBeHex(value, 32);
export const eventRecord = (category: number, ...fields: string[]) => ethers.concat([ethers.toBeHex(category, 1), ...fields]);
// Pipeline records: Pipeline lists commands; Step and State carry a 1-byte step index.
export const pipelineRecord = (account: string, cmds: bigint[]) => eventRecord(Category.Pipeline, account, ...cmds.map(cmd => word(cmd)));
export const stepRecord = (index: number, value: bigint, input?: string) => eventRecord(Category.Input,
  ethers.toBeHex(index | (value ? 0x40 : 0), 1), ...(value ? [word(value)] : []), ...(input === undefined ? [] : [input]));
export const stateRecord = (index: number, payload: string) => eventRecord(Category.State, ethers.toBeHex(index, 1), payload);
export const balanceRecord = (account: string, asset: string, balance: bigint) => eventRecord(Category.Balance, account, asset, word(balance));
export function categoryPayload(log: RawLog, category: number, size?: number): string | null {
  if (log.topics.length || ethers.dataLength(log.data) === 0 || Number(ethers.dataSlice(log.data, 0, 1)) !== category) return null;
  const payload = ethers.dataSlice(log.data, 1);
  if (size !== undefined && ethers.dataLength(payload) !== size) throw new Error("Invalid category record length");
  return payload;
}
