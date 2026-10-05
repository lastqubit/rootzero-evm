import hre from "hardhat";
import { ethers } from "ethers";

let _connection: Awaited<ReturnType<typeof hre.network.connect>> | null = null;

async function getConnection() {
  if (!_connection) {
    _connection = await hre.network.getOrCreate();
  }
  return _connection;
}

export async function getProvider() {
  const conn = await getConnection();
  // Hardhat mines synchronously; cached gas estimates can outlive state changes.
  return new ethers.BrowserProvider(conn.provider, undefined, { cacheTimeout: -1 });
}

export async function getSigner(index = 0) {
  const provider = await getProvider();
  return provider.getSigner(index);
}

export async function getSigners(count = 5) {
  const provider = await getProvider();
  const accounts = await provider.listAccounts();
  return Promise.all(accounts.slice(0, count).map((_, i) => provider.getSigner(i)));
}

export async function deploy(contractName: string, ...args: unknown[]): Promise<any> {
  const signer = await getSigner();
  const artifact = await hre.artifacts.readArtifact(contractName);
  const factory = new ethers.ContractFactory(artifact.abi, artifact.bytecode, signer);
  const contract = await factory.deploy(...args);
  await contract.waitForDeployment();
  return contract;
}

export async function deployAs(signerIndex: number, contractName: string, ...args: unknown[]): Promise<any> {
  const signer = await getSigner(signerIndex);
  const artifact = await hre.artifacts.readArtifact(contractName);
  const factory = new ethers.ContractFactory(artifact.abi, artifact.bytecode, signer);
  const contract = await factory.deploy(...args);
  await contract.waitForDeployment();
  return contract;
}

const HostPrefix = 0x03020200n;
const CommandPrefix = 0x03020300n;
const PortPrefix = 0x03020400n;
const QueryPrefix = 0x03020500n;
const GuardPrefix = 0x03020600n;

function selector(signature: string) {
  if (/^0x[0-9a-fA-F]{8}$/.test(signature)) return BigInt(signature);
  return BigInt(ethers.dataSlice(ethers.id(signature), 0, 4));
}

async function nodeId(
  prefix: bigint,
  signature: string,
  target: { getAddress(): Promise<string> } | string,
  flags = 0n,
) {
  const addr = typeof target === "string" ? target : await target.getAddress();
  const provider = await getProvider();
  const network = await provider.getNetwork();
  return ((prefix | flags) << 224n) | (network.chainId << 192n) | (selector(signature) << 160n) | BigInt(addr);
}

export async function hostId(target: { getAddress(): Promise<string> } | string) {
  const addr = typeof target === "string" ? target : await target.getAddress();
  const provider = await getProvider();
  const network = await provider.getNetwork();
  return (HostPrefix << 224n) | (network.chainId << 192n) | BigInt(addr);
}

export function commandId(
  signature: string,
  target: { getAddress(): Promise<string> } | string,
  flags = 0n,
) {
  return nodeId(CommandPrefix, signature, target, flags);
}

export function portId(signature: string, target: { getAddress(): Promise<string> } | string, flags = 0n) {
  return nodeId(PortPrefix, signature, target, flags);
}

export function queryId(signature: string, target: { getAddress(): Promise<string> } | string) {
  return nodeId(QueryPrefix, signature, target);
}

export function guardId(signature: string, target: { getAddress(): Promise<string> } | string) {
  return nodeId(GuardPrefix, signature, target);
}


