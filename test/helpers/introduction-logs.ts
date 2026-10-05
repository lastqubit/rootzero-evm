import { decodeBlockLog, decodeFixedBlock, type RawLog } from "./log-blocks.js";
import { ethers } from "ethers";
import { Keys } from "./blocks.js";

export const HostIntroduce = 0x20000002n | (9n << 32n);

export function decodeIntroductionLog(log: RawLog) {
  const record = decodeBlockLog(log);
  if (!record || (record.prefix !== HostIntroduce)) return null;
  const payload = decodeFixedBlock(record.stream, Keys.Introduction, 96);
  return { peer: BigInt(ethers.dataSlice(payload, 0, 32)), origin: ethers.dataSlice(payload, 32, 64), blocknum: BigInt(ethers.dataSlice(payload, 64, 96)) };
}
