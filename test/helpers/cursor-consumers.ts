import { ethers } from "ethers";
import { concat, encodeBlock, encodePositionConstraintsBlock, Keys } from "./blocks.js";

export const consumerKinds = ["Envelope", "Step", "Chain"] as const;
export const size = (s: string) => ethers.getBytes(s).length;
export const balance = encodeBlock(Keys.Balance, concat(ethers.toBeHex(1, 32), ethers.toBeHex(7, 32)));
export const constraints = encodePositionConstraintsBlock(ethers.toBeHex(1, 32), 7n, ethers.toBeHex(2, 32), 3n);
export function consumerBlock(kind: string, children: number) {
  if (kind === "Chain") return concat(balance, constraints);
  const body = concat(...Array(children).fill(balance));
  return kind === "Envelope" ? encodeBlock(Keys.Bytes, body)
    : encodeBlock(Keys.Step, concat(ethers.toBeHex(11, 32), ethers.toBeHex(13, 32), encodeBlock(Keys.Bytes, body)));
}
export function expectedConsumer(kind: string, children: number, count: number) {
  return {
    sum: BigInt(count * (kind === "Chain" ? 8 : children * 8 + (kind === "Step" ? 24 : 0))),
    count: BigInt(count * (kind === "Chain" ? 1 : children)),
  };
}
