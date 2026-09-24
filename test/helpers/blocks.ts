import { ethers } from "ethers";

// Block key derivation: bytes4(keccak256("#name"))
export function blockKey(name: string): string {
  return ethers.dataSlice(ethers.id(name), 0, 4);
}

export function localKey(value: number): string {
  return ethers.toBeHex(value, 4);
}

export function exactSpec(key: string, size: number): bigint {
  const value = BigInt(size);
  return (BigInt(key) << 224n) | (value << 192n) | (value << 160n) | (value << 136n);
}

export function rangedSpec(key: string, min: number, max: number, hint: number): bigint {
  return (BigInt(key) << 224n)
    | (BigInt(min) << 192n)
    | (BigInt(max) << 160n)
    | (BigInt(hint) << 136n);
}

export function endpointDescriptor({
  state = Keys.Empty, stateHint = 0, input = Keys.Empty, inputHint = 0,
  output = Keys.Empty, funded = false, admin = false, handoff = false,
}: {
  state?: string; stateHint?: number; input?: string; inputHint?: number;
  output?: string | bigint; funded?: boolean; admin?: boolean; handoff?: boolean;
}): bigint {
  const flags = (funded ? 1n : 0n) | (admin ? 2n : 0n) | (handoff ? 128n : 0n);
  const outputSpec = typeof output === "bigint" ? output : output === Keys.Empty
    ? 0n : (() => { throw new Error("non-empty output lanes require a spec"); })();
  const stateKey = BigInt(state), inputKey = BigInt(input), outputKey = outputSpec >> 224n;
  const sourceKey = stateKey || inputKey;
  const sourceSize = sourceKey === 0n ? 0n : BigInt(8 + (stateKey !== 0n ? stateHint : inputHint));
  const outputSize = outputKey === 0n ? 0n : 8n + ((outputSpec >> 136n) & 0xffffffn);
  return (stateKey << 224n) | (inputKey << 192n) | (outputKey << 160n)
    | (sourceKey << 128n) | (sourceSize << 96n) | (outputSize << 64n)
    | ((stateKey !== 0n ? 64n : 0n) << 56n)
    | (((stateKey !== 0n ? 1n : 0n) | (inputKey !== 0n ? 2n : 0n)) << 48n) | flags;
}

// Known block keys
export const Keys = {
  Empty: "0x00000000",
  Local: localKey(1),
  Bytes: blockKey("#bytes"),
  String: blockKey("#string"),
  List: blockKey("#list"),

  // Live pipeline state
  Balance: blockKey("#balance"),
  Custody: blockKey("#custody"),
  Position: blockKey("#position"),

  // Input and value blocks
  Amount: blockKey("#amount"),
  Limits: blockKey("#limits"),
  Quote: blockKey("#quote"),
  Bootstrap: blockKey("#bootstrap"),
  Allocation: blockKey("#allocation"),
  Allowance: blockKey("#allowance"),
  Account: blockKey("#account"),
  Transaction: blockKey("#transaction"),

  // Composite and annotation blocks
  Node: blockKey("#node"),
  Asset: blockKey("#asset"),
  Step: blockKey("#step"),
  Call: blockKey("#call"),
  Context: blockKey("#context"),
  Recover: blockKey("#recover"),
  Relay: blockKey("#relay"),
  Dispatch: blockKey("#dispatch"),
  Label: blockKey("#label"),
  Annotation: blockKey("#annotation"),
  Action: blockKey("#action"),
  Counterparty: blockKey("#counterparty"),
  Schema: blockKey("#schema"),
  Status: blockKey("#status"),
  AssetLiability: blockKey("#assetLiability"),
  AccountAsset: blockKey("#accountAsset"),
  HostAsset: blockKey("#hostAsset"),
  AccountAmount: blockKey("#accountAmount"),
  HostAmount: blockKey("#hostAmount"),
  HostAccountAsset: blockKey("#hostAccountAsset"),
  HostAccountAmount: blockKey("#hostAccountAmount"),
} as const;

// Pad a bigint or hex string to 32 bytes
export function pad32(value: bigint | string): string {
  if (typeof value === "bigint") {
    return ethers.zeroPadValue(ethers.toBeHex(value), 32);
  }
  return ethers.zeroPadValue(value, 32);
}

const USER_PREFIX = 0x03010300n;

export function encodeUserAccount(addr: string): string {
  const account = (USER_PREFIX << 224n) | BigInt(ethers.zeroPadValue(addr, 20));
  return ethers.zeroPadValue(ethers.toBeHex(account), 32);
}

// Encode a 4-byte big-endian uint32
function encodeUint32(value: number): string {
  return ethers.toBeHex(value, 4);
}

// Build a block header + payload
export function encodeBlock(key: string, payload: string): string {
  const payloadBytes = ethers.getBytes(payload);
  return ethers.concat([key, encodeUint32(payloadBytes.length), payload]);
}

export function encodeAmountBlock(asset: string, amount: bigint): string {
  return encodeBlock(Keys.Amount, ethers.concat([pad32(asset), pad32(amount)]));
}

export function encodeBootstrapBlock(asset: string, amount: bigint, budget: bigint): string {
  return encodeBlock(Keys.Bootstrap, ethers.concat([pad32(asset), pad32(amount), pad32(budget)]));
}

export function encodeBalanceBlock(asset: string, amount: bigint): string {
  return encodeBlock(Keys.Balance, ethers.concat([pad32(asset), pad32(amount)]));
}

/** Debt is a POSITION with its asset side and counterparty set to zero. */
export function encodeLiabilityPosition(liability: string, debt: bigint): string {
  return encodePositionBlock(ethers.ZeroHash, 0n, liability, debt);
}

export function encodeHostAccountAssetBlock(host: bigint, account: string, asset: string): string {
  return encodeBlock(Keys.HostAccountAsset, ethers.concat([pad32(host), pad32(account), pad32(asset)]));
}

export function encodeAccountAssetBlock(account: string, asset: string): string {
  return encodeBlock(Keys.AccountAsset, ethers.concat([pad32(account), pad32(asset)]));
}

export function encodeAssetLiabilityBlock(asset: string, liability: string): string {
  return encodeBlock(Keys.AssetLiability, ethers.concat([pad32(asset), pad32(liability)]));
}

export function encodeHostAssetBlock(host: bigint, asset: string): string {
  return encodeBlock(Keys.HostAsset, ethers.concat([pad32(host), pad32(asset)]));
}

export function encodeAccountAmountBlock(account: string, asset: string, amount: bigint): string {
  return encodeBlock(Keys.AccountAmount, ethers.concat([pad32(account), pad32(asset), pad32(amount)]));
}

export function encodeAllocationBlock(host: bigint, asset: string, amount: bigint): string {
  return encodeBlock(Keys.Allocation, ethers.concat([pad32(host), pad32(asset), pad32(amount)]));
}

export function encodeAllowanceBlock(host: bigint, asset: string, amount: bigint): string {
  return encodeBlock(Keys.Allowance, ethers.concat([pad32(host), pad32(asset), pad32(amount)]));
}

export function encodeCustodyBlock(host: bigint, asset: string, amount: bigint): string {
  return encodeBlock(Keys.Custody, ethers.concat([pad32(host), pad32(asset), pad32(amount)]));
}

export const MaxUint128 = (1n << 128n) - 1n;

/** Literal uint128 minimum asset amount and maximum total debt. */
export function packLimits(amount: bigint, debt: bigint): bigint {
  if (amount < 0n || amount > MaxUint128 || debt < 0n || debt > MaxUint128) {
    throw new RangeError("Limits must fit uint128 lanes");
  }
  return (amount << 128n) | debt;
}

/** Expected outcome: amount is a minimum and debt is a maximum. */
export function encodeLimitsBlock(amount: bigint, debt: bigint): string {
  return encodeBlock(Keys.Limits, pad32(packLimits(amount, debt)));
}

export function encodeQuoteBlock(asset: string, liability: string, limits: bigint): string {
  return encodeBlock(Keys.Quote, ethers.concat([pad32(asset), pad32(liability), pad32(limits)]));
}

export function encodePositionBlock(
  asset: string,
  amount: bigint,
  liability: string,
  debt: bigint,
  counterparty: string = ethers.ZeroHash,
): string {
  return encodeBlock(Keys.Position, ethers.concat([
    pad32(asset),
    pad32(amount),
    pad32(liability),
    pad32(debt),
    pad32(counterparty),
  ]));
}

export function encodeAccountBlock(account: string): string {
  return encodeBlock(Keys.Account, pad32(account));
}

export function encodeNodeBlock(id: bigint): string {
  return encodeBlock(Keys.Node, pad32(id));
}

export function encodeAssetBlock(asset: string): string {
  return encodeBlock(Keys.Asset, pad32(asset));
}

export function encodeTxBlock(from: string, to: string, asset: string, amount: bigint): string {
  return encodeBlock(Keys.Transaction, ethers.concat([pad32(from), pad32(to), pad32(asset), pad32(amount)]));
}

export function encodeStepBlock(cmd: bigint, value: bigint, input: string): string {
  return encodeBlock(Keys.Step, ethers.concat([
    pad32(cmd),
    pad32(value),
    encodeBytesBlock(input),
  ]));
}

export function encodeCallBlock(target: bigint, value: bigint, data: string): string {
  return encodeBlock(Keys.Call, ethers.concat([pad32(target), pad32(value), encodeBytesBlock(data)]));
}

export function encodeContextBlock(account: string, state: string, input: string): string {
  return encodeBlock(Keys.Context, ethers.concat([pad32(account), encodeBytesBlock(state), encodeBytesBlock(input)]));
}

export function encodeRelayInputBlock(portal: bigint, resources: bigint): string {
  return encodeBlock(localKey(3), ethers.concat([pad32(portal), pad32(resources)]));
}

export function encodeRecoverBlock(handler: bigint, resources: bigint, key: string, witness: string): string {
  return encodeBlock(Keys.Recover, ethers.concat([pad32(handler), pad32(resources), pad32(key), encodeBytesBlock(witness)]));
}

export function encodeRelayBlock(input: string, steps: string): string {
  return encodeBlock(Keys.Relay, ethers.concat([encodeBytesBlock(input), encodeBytesBlock(steps)]));
}

export function encodeDispatchBlock(portal: bigint, resources: bigint, payload: string): string {
  return encodeBlock(Keys.Dispatch, ethers.concat([pad32(portal), pad32(resources), encodeBytesBlock(payload)]));
}

export function encodeBytesBlock(data: string): string {
  return encodeBlock(Keys.Bytes, data);
}

export function encodeStringBlock(data: string): string {
  return encodeBlock(Keys.String, ethers.hexlify(ethers.toUtf8Bytes(data)));
}

export function encodeLabelBlock(namespace: string, name: string): string {
  return encodeBlock(Keys.Label, ethers.concat([pad32(namespace), encodeStringBlock(name)]));
}

export function encodeAnnotationBlock(entity: bigint, data: string): string {
  return encodeBlock(Keys.Annotation, ethers.concat([pad32(entity), encodeBytesBlock(data)]));
}

export function encodeActionBlock(action: bigint): string {
  return encodeBlock(Keys.Action, pad32(action));
}

export function encodeCounterpartyBlock(account: string): string {
  return encodeBlock(Keys.Counterparty, pad32(account));
}

export function encodeSchemaBlock(spec: bigint, body: string): string {
  return encodeBlock(Keys.Schema, ethers.concat([pad32(spec), encodeStringBlock(body)]));
}

export function encodeStatusBlock(code: bigint): string {
  return encodeBlock(Keys.Status, pad32(code));
}

export function encodeListBlock(...members: string[]): string {
  return encodeBlock(Keys.List, concat(...members));
}

export function concat(...parts: string[]): string {
  return ethers.concat(parts);
}

// Command args suffix appended when computing command selectors
const COMMAND_ARGS = "(bytes)";
const PORT_ARGS = "(bytes)";
const GUARD_ARGS = "(bytes)";

export function commandSelector(name: string): string {
  return ethers.dataSlice(ethers.id(name + COMMAND_ARGS), 0, 4);
}

export function portSelector(name: string): string {
  return ethers.dataSlice(ethers.id(name + PORT_ARGS), 0, 4);
}

export function guardSelector(name: string): string {
  return ethers.dataSlice(ethers.id(name + GUARD_ARGS), 0, 4);
}


/** Derive a host account from the chain and address of an EVM host node ID. */
export function encodeHostAccount(host: bigint): string {
  return ethers.toBeHex((0x03010200n << 224n) | (host & (0xffffffffn << 192n))
    | (host & ((1n << 160n) - 1n)), 32);
}

// Flat debit/credit pair consumed by BookPort.
export function encodeBookPortPair(debit: string, credit: string): string {
  return concat(debit, credit);
}
