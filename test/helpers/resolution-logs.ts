import { categoryPayload, Category } from "./event-records.js";
import { type RawLog } from "./log-blocks.js";
import { expect } from "chai";
import { ethers } from "ethers";


export function decodeResolutionLog(log: RawLog) {
  const payload = categoryPayload(log, Category.Resolution, 65);
  if (payload === null) return null;
  const status = Number(ethers.dataSlice(payload, 64, 65));
  if (status > 1) throw new Error("Invalid resolution status");
  return { resolved: status === 1, key: ethers.dataSlice(payload, 0, 32), digest: ethers.dataSlice(payload, 32, 64) };
}

export async function expectResolution(tx: any, host: any, key: string, digest: string, resolved: boolean) {
  const receipt = await (await tx).wait();
  const address = (await host.getAddress()).toLowerCase();
  const records = receipt.logs.filter((log: any) => log.address.toLowerCase() === address)
    .map(decodeResolutionLog).filter((record: any) => record !== null);
  expect(records).deep.eq([{ resolved, key, digest }]);
}
