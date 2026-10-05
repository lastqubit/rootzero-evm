import { ethers } from "ethers";

export interface RawLog {
  topics: readonly string[];
  data: string;
}

export function decodeBlockLog(log: RawLog): { prefix: bigint; stream: string } | null {
  if (log.topics.length || ethers.dataLength(log.data) < 32) return null;
  return { prefix: BigInt(ethers.dataSlice(log.data, 0, 32)), stream: ethers.dataSlice(log.data, 32) };
}

export function decodeBlocks(data: string): { key: string; payload: string }[] {
  const size = ethers.dataLength(data);
  const result: { key: string; payload: string }[] = [];
  for (let offset = 0; offset < size;) {
    if (offset + 8 > size) throw new Error("Truncated block header");
    const key = ethers.dataSlice(data, offset, offset + 4);
    const end = offset + 8 + Number(BigInt(ethers.dataSlice(data, offset + 4, offset + 8)));
    if (end > size) throw new Error("Truncated block payload");
    result.push({ key, payload: ethers.dataSlice(data, offset + 8, end) });
    offset = end;
  }
  return result;
}

export function decodeFixedBlock(stream: string, key: string, size: number): string {
  const blocks = decodeBlocks(stream);
  if (blocks.length !== 1 || blocks[0].key !== key || ethers.dataLength(blocks[0].payload) !== size)
    throw new Error("Unexpected fixed block");
  return blocks[0].payload;
}
