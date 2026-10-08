import type { RawLog } from "./log-blocks.js";
import { ethers } from "ethers";
import { categoryPayload, Category } from "./event-records.js";
export function decodeMetadataLog(log: RawLog) {
  const metadata = categoryPayload(log, Category.Metadata);
  if (metadata === null) return [];
  if (ethers.dataLength(metadata) < 32) throw new Error("Truncated metadata subject");
  return [{ entity: BigInt(ethers.dataSlice(metadata, 0, 32)), data: ethers.dataSlice(metadata, 32) }];
}
