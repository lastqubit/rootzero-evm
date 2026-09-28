import { ethers } from "ethers";
import { Keys, encodeBlock } from "./blocks.js";

export const executeCases = ["Bootstrap", "DebitAccount", "CreditAccount", "Cashout", "Settle", "Authorize", "CheckBalance", "CheckPosition"] as const;
export const word = (n: bigint | number) => ethers.toBeHex(n, 32);
export const block = (key: string, fields: (bigint | number)[]) => encodeBlock(key, ethers.concat(fields.map(word)));
export function executeStreams(name: string, count: number, asset: bigint) {
  const balances = ethers.concat(Array.from({ length: count }, (_, i) => block(Keys.Balance, [asset, 7 + i])));
  const positions = ethers.concat(Array.from({ length: count }, (_, i) => block(Keys.Position, [asset, 7 + i, 2, 3, 9])));
  if (name === "CreditAccount" || name === "Cashout") return [balances, "0x"];
  if (name === "Settle") return [positions, "0x"];
  if (name === "CheckBalance") return [balances, ethers.concat(Array.from({ length: count }, () => block(Keys.BalanceConstraints, [asset, 0, ethers.MaxUint256])))];
  if (name === "CheckPosition") return [positions, ethers.concat(Array.from({ length: count }, () => block(Keys.PositionConstraints, [asset, 0, 2, 100])))];
  const [key, fields] = name === "Bootstrap" ? [Keys.Bootstrap, [asset, 7, 3]] : name === "DebitAccount" ? [Keys.Amount, [asset, 7]] : [Keys.Node, [13]];
  return ["0x", ethers.concat(Array.from({ length: count }, () => block(key as string, fields as (number | bigint)[])))];
}
