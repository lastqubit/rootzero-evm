import { ethers } from "ethers";
import type { RawLog } from "./log-blocks.js";
import { categoryPayload, Category } from "./event-records.js";
export function decodeIntroductionLog(log: RawLog) {
  const payload = categoryPayload(log, Category.Introduction);
  if (payload === null) return null;
  if (ethers.dataLength(payload) < 96) throw new Error("Invalid introduction record length");
  return { peer: BigInt(ethers.dataSlice(payload, 0, 32)), origin: ethers.dataSlice(payload, 32, 64), blocknum: BigInt(ethers.dataSlice(payload, 64, 96)), name: ethers.toUtf8String(ethers.dataSlice(payload, 96)) };
}
