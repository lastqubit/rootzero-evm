import { decodeBlockLog, decodeBlocks, type RawLog } from "./log-blocks.js";
import { ethers } from "ethers";
import { Keys } from "./blocks.js";

export const HostAnnotate = 0x20000002n | (8n << 32n);

// Decode only known annotation envelopes; other LOG0 families are unrelated.
export function decodeAnnotationLog(log: RawLog, command?: bigint) {
  const record = decodeBlockLog(log);
  if (!record || (record.prefix !== HostAnnotate && record.prefix !== command)) return [];
  const { prefix } = record;
  let { stream } = record;
  if (prefix !== HostAnnotate) {
    const wrapped = decodeBlocks(stream);
    if (wrapped.length !== 1 || wrapped[0].key !== Keys.Input) throw new Error("Expected INPUT wrapper");
    stream = wrapped[0].payload;
  }
  return decodeBlocks(stream).map(({ key, payload }) => {
    if (key !== Keys.Annotation || ethers.dataLength(payload) < 40) throw new Error("Expected ANNOTATION");
    const entity = BigInt(ethers.dataSlice(payload, 0, 32));
    const children = decodeBlocks(ethers.dataSlice(payload, 32));
    if (children.length !== 1 || children[0].key !== Keys.Bytes) throw new Error("Expected BYTES child");
    return { entity, data: children[0].payload };
  });
}
