import { decodeIntroductionLog } from "./helpers/introduction-logs.js";
import { expect } from "chai";
import { ethers } from "ethers";
import { deploy, getSigner, getProvider, hostId } from "./helpers/setup.js";
import hre from "hardhat";
import "./helpers/matchers.js";
import { encodeUserAccount } from "./helpers/blocks.js";

describe("Host Introduction", () => {
  let rootzero: Awaited<ReturnType<typeof deploy>>;

  before(async () => {
    rootzero = await deploy("TestHost", 0n);
  });

  it("introduces host on construction when the rootzero runtime is set", async () => {
    const artifact = await hre.artifacts.readArtifact("TestHost");
    const provider = await getProvider();
    const factory = new ethers.ContractFactory(artifact.abi, artifact.bytecode, await provider.getSigner(0));
    const contract = await factory.deploy(await rootzero.host());
    const receipt = await contract.deploymentTransaction()!.wait();

    const receiver = (await rootzero.getAddress()).toLowerCase();
    const logs = receipt!.logs.filter(log => log.address.toLowerCase() === receiver)
      .map(decodeIntroductionLog).filter(value => value !== null);
    expect(logs).deep.eq([{
      peer: await (contract as any).host(),
      origin: encodeUserAccount(await (await getSigner(0)).getAddress()),
      blocknum: BigInt(receipt!.blockNumber), name: "TestHost",
    }]);
  });

  it("introduces a command host to its contract commander", async () => {
    const artifact = await hre.artifacts.readArtifact("TestMinimalCommandHost");
    const provider = await getProvider();
    const factory = new ethers.ContractFactory(artifact.abi, artifact.bytecode, await provider.getSigner(0));
    const contract = await factory.deploy(await rootzero.host());
    const receipt = await contract.deploymentTransaction()!.wait();

    const receiver = (await rootzero.getAddress()).toLowerCase();
    const introduced = receipt!.logs.filter(log => log.address.toLowerCase() === receiver)
      .map(decodeIntroductionLog).find(value => value !== null);
    expect(introduced).to.not.equal(undefined);
    expect(introduced!.peer).to.equal(await (contract as any).host());
    expect(introduced!.name).eq("TestMinimalCommandHost");
  });

  it("rejects deployment when a contract commander cannot accept introductions", async () => {
    const commander = await deploy("TestExecuteTarget");

    for (const host of ["TestMinimalCommandHost", "TestBareHost"]) {
      let rejected = false;
      try {
        await deploy(host, await hostId(commander));
      } catch {
        rejected = true;
      }
      expect(rejected).to.equal(true);
    }
  });

  it("does NOT introduce when the commander host ID is zero", async () => {
    const host = await deploy("TestHost", 0n);
    expect(await host.getAddress()).to.not.equal(ethers.ZeroAddress);
    const receipt = await host.deploymentTransaction().wait();
    expect(receipt.logs.map(decodeIntroductionLog).filter(Boolean)).deep.eq([]);
  });

  it("introduce rejects claims that do not match the caller address", async () => {
    const signer = await getSigner(0);
    const claimedHostId = 12345n;

    await expect(
      rootzero.connect(signer).introduce(claimedHostId, 0n, "claimed")
    ).to.be.revertedWithCustomError(rootzero, "InvalidId");
  });

  it("introduce succeeds when id matches caller address", async () => {
    const signer = await getSigner(0);
    const callerAddr = await signer.getAddress();

    const CHAIN_ID = 31337n;
    const HOST_PREFIX = 0x03020200n;
    const correctHostId = (HOST_PREFIX << 224n) | (CHAIN_ID << 192n) | BigInt(callerAddr);

    const receipt = await (await rootzero.connect(signer).introduce(correctHostId, 1n, "peer")).wait();
    expect(receipt.logs.map(decodeIntroductionLog)).deep.eq([{
      peer: correctHostId, origin: encodeUserAccount(callerAddr), blocknum: 1n, name: "peer",
    }]);
    expect(receipt.logs[0].address.toLowerCase()).eq((await rootzero.getAddress()).toLowerCase());
  });

  it("Introduction preserves a caller-supplied full-width block claim", async () => {
    const signer = await getSigner(0);
    const callerAddr = await signer.getAddress();
    const CHAIN_ID = 31337n;
    const HOST_PREFIX = 0x03020200n;
    const hostId = (HOST_PREFIX << 224n) | (CHAIN_ID << 192n) | BigInt(callerAddr);

    for (const blocknum of [0n, ethers.MaxUint256]) {
      const receipt = await (await rootzero.connect(signer).introduce(hostId, blocknum, "peer")).wait();
      expect(receipt.logs.map(decodeIntroductionLog)).deep.eq([{
        peer: hostId, origin: encodeUserAccount(callerAddr), blocknum, name: "peer",
      }]);
    }
    expect(rootzero.interface.getEvent("Introduction")).eq(null);
    expect(rootzero.interface.getEvent("EventAbi")).eq(null);
  });
});
