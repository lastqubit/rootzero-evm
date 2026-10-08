import { ethers } from "ethers";
import type { RawLog } from "./log-blocks.js";
import { categoryPayload, Category } from "./event-records.js";
import { Keys } from "./blocks.js";
export const EndpointKey = Keys.Endpoint;
export function decodeEndpointLog(log: RawLog): [bigint, bigint, bigint, bigint, string] | null {
  const payload = categoryPayload(log, Category.Endpoint);
  if (payload === null) return null;
  if (ethers.dataLength(payload) < 128) throw new Error("Invalid endpoint record length");
  const words = [0, 1, 2, 3].map(i => BigInt(ethers.dataSlice(payload, i * 32, (i + 1) * 32)));
  return [words[0], words[1], words[2], words[3], ethers.toUtf8String(ethers.dataSlice(payload, 128))];
}
