import { expect } from "chai";
import { ethers } from "ethers";
import { deploy, getProvider, hostId } from "./helpers/setup.js";

describe("Portal gas recovery", function () {
  this.timeout(120_000);

  it("retains attached value and the digest when the pipe exhausts its gas", async () => {
    const pipe = await deploy("TestOutOfGasPipe");
    const portal = await deploy("TestPortalGas", await hostId(pipe));
    const key = ethers.toBeHex(1, 32);
    const message = "0xabcdef";
    await (await portal.testForward(key, message, { value: 7n, gasLimit: 200_000 })).wait();
    expect(await portal.getUnresolved(key)).to.equal(ethers.keccak256(message));
    const provider = await getProvider();
    expect(await provider.getBalance(await portal.getAddress())).to.equal(7n);
    expect(await provider.getBalance(await pipe.getAddress())).to.equal(0n);
  });

  it("skips the pipe and stores directly when only recovery fits", async () => {
    const pipe = await deploy("TestOutOfGasPipe");
    const portal = await deploy("TestPortalGas", await hostId(pipe));
    const key = ethers.toBeHex(1, 32);
    const tx = await portal.testForward(key, "0x", { value: 7n, gasLimit: 50_000 });
    await tx.wait();
    expect(await portal.getUnresolved(key)).to.equal(ethers.keccak256("0x"));
    const provider = await getProvider();
    const trace = await provider.send("debug_traceTransaction", [tx.hash,
      { disableMemory: true, disableStack: true, disableStorage: true }]);
    expect(trace.structLogs.some((step: any) => step.op === "CALL")).to.equal(false);
    expect(await provider.getBalance(await portal.getAddress())).to.equal(7n);
  });

  it("honors a derived constructor's larger fixed reserve", async () => {
    const pipe = await deploy("TestOutOfGasPipe");
    const provider = await getProvider();
    const remaining: number[] = [];
    for (const name of ["TestPortalGas", "TestPortalGasExtraReserve"]) {
      const portal = await deploy(name, await hostId(pipe));
      const tx = await portal.testForward(ethers.toBeHex(1, 32), "0x", { gasLimit: 200_000 });
      await tx.wait();
      const trace = await provider.send("debug_traceTransaction", [tx.hash,
        { disableMemory: true, disableStack: true, disableStorage: true }]);
      const call = trace.structLogs.findIndex((s: any) => s.depth === 1 && s.op === "CALL");
      expect(call).to.be.greaterThan(-1);
      remaining.push(Number(trace.structLogs.slice(call + 1).find((s: any) => s.depth === 1).gas));
    }
    expect(remaining[1] - remaining[0]).to.equal(20_000);
  });

  it("reverts without storing a digest when even direct storage has insufficient gas", async () => {
    const pipe = await deploy("TestOutOfGasPipe");
    const portal = await deploy("TestPortalGas", await hostId(pipe));
    const key = ethers.toBeHex(1, 32);
    let failed = false;
    try {
      await (await portal.testForward(key, "0x" + "ab".repeat(256),
        { value: 7n, gasLimit: 40_000 })).wait();
    } catch (error: any) {
      const detail = String(error.message) + JSON.stringify(error.info?.error);
      expect(/out of gas|outofgas/i.test(detail) || error.receipt?.status === 0).to.equal(true);
      failed = true;
    }
    expect(failed).to.equal(true);
    expect(await portal.getUnresolved(key)).to.equal(ethers.ZeroHash);
    const provider = await getProvider();
    expect(await provider.getBalance(await portal.getAddress())).to.equal(0n);
    expect(await provider.getBalance(await pipe.getAddress())).to.equal(0n);
  });
});
