import { decodeBlockLog, decodeFixedBlock, type RawLog } from "./log-blocks.js";
import { expect } from "chai";
import { ethers } from "ethers";
import { Keys } from "./blocks.js";

export const HostUnresolved = 0x20000002n | (0xa0000010n << 32n);
export const HostResolved = 0x20000002n | (0xa0000011n << 32n);

export function decodeResolutionLog(log: RawLog) {
  const record = decodeBlockLog(log);
  if (!record || (record.prefix !== HostResolved && record.prefix !== HostUnresolved)) return null;
  const payload = decodeFixedBlock(record.stream, Keys.Resolution, 64);
  return { codes: record.prefix, key: ethers.dataSlice(payload, 0, 32), digest: ethers.dataSlice(payload, 32, 64) };
}

export async function expectResolution(tx: any, host: any, key: string, digest: string, codes: bigint) {
  const receipt = await (await tx).wait();
  const address = (await host.getAddress()).toLowerCase();
  const records = receipt.logs.filter((log: any) => log.address.toLowerCase() === address)
    .map(decodeResolutionLog).filter((record: any) => record !== null);
  expect(records).deep.eq([{ codes, key, digest }]);
}
