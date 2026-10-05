import { decodeBlockLog, decodeFixedBlock, type RawLog } from "./log-blocks.js";
import { ethers } from "ethers";
import { Keys } from "./blocks.js";

export const HostAdd = 0x20000002n | (4n << 32n);
export const EndpointKey = Keys.Endpoint;

export function decodeEndpointLog(log: RawLog): bigint[] | null {
  const record = decodeBlockLog(log);
  if (!record || (record.prefix !== HostAdd)) return null;
  // HostAdd can register other block kinds as well.
  if (ethers.dataLength(record.stream) < 4 || ethers.dataSlice(record.stream, 0, 4) !== Keys.Endpoint) return null;
  const payload = decodeFixedBlock(record.stream, Keys.Endpoint, 128);
  return [0, 1, 2, 3].map(i => BigInt(ethers.dataSlice(payload, i * 32, (i + 1) * 32)));
}
