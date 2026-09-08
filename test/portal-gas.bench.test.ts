import { expect } from "chai";
import { ethers } from "ethers";
import { mkdirSync, writeFileSync } from "node:fs";
import { deploy, getProvider, getSigner, hostId } from "./helpers/setup.js";

describe("Portal pipe out-of-gas benchmark", function () {
  this.timeout(120_000);

  it("finds the transaction gas boundary for retaining a failed message", async () => {
    const pipe = await deploy("TestOutOfGasPipe");
    const portal = await deploy("TestPortalGas", await hostId(pipe));
    const provider = await getProvider();
    const from = await (await getSigner()).getAddress();
    const to = await portal.getAddress();
    const results: object[] = [];
    let keyIndex = 0;

    for (const size of [0, 256, 4096, 65536]) {
      for (const state of ["fresh", "overwrite", "unchanged"] as const) {
        const key = ethers.toBeHex(++keyIndex, 32);
        const message = "0x" + "ab".repeat(size);
        const digest = ethers.keccak256(message);
        if (state !== "fresh") {
          const previous = state === "unchanged" ? message : "0x1234";
          await (await portal.testForward(key, previous, { gasLimit: 8_000_000 })).wait();
        }
        const before = await portal.getUnresolved(key);
        const data = portal.interface.encodeFunctionData("testForward", [key, message]);
        async function succeeds(gas: number) {
          try {
            const result = await provider.send("eth_call", [{ from, to, data, gas: ethers.toQuantity(gas) }, "latest"]);
            expect(portal.interface.decodeFunctionResult("testForward", result)[0]).to.equal(digest);
            return true;
          } catch (error: any) {
            // Do not mistake infrastructure or assertion failures for an EVM OOG.
            const detail = String(error.message) + JSON.stringify(error.info);
            if (!/out of gas|outofgas|requires at least|requires gas floor|intrinsic gas too low/i.test(detail)) {
              throw new Error(`Unexpected failure at gas ${gas}: ${JSON.stringify(error.info?.error)}`, { cause: error });
            }
            return false;
          }
        }

        let low = 21_000;
        let high = 8_000_000;
        expect(await succeeds(low)).to.equal(false);
        expect(await succeeds(high)).to.equal(true);
        while (high - low > 1) {
          const middle = Math.floor((low + high) / 2);
          if (await succeeds(middle)) high = middle;
          else low = middle;
        }
        expect(await succeeds(high - 1)).to.equal(false);
        expect(await portal.getUnresolved(key)).to.equal(before);
        const tx = await portal.testForward(key, message, { gasLimit: high });
        const receipt = await tx.wait();
        expect(receipt.status).to.equal(1);
        const trace = await provider.send("debug_traceTransaction", [tx.hash,
          { disableMemory: true, disableStack: true, disableStorage: true }]);
        const callIndex = trace.structLogs.findIndex((step: any) => step.depth === 1 && step.op === "CALL");
        // Minimum successful gas may skip delivery and store directly.
        const afterCall = callIndex < 0 ? undefined
          : trace.structLogs.slice(callIndex + 1).find((step: any) => step.depth === 1);
        expect(await portal.getUnresolved(key)).to.equal(digest);
        const events = receipt.logs.map((log: any) => portal.interface.parseLog(log));
        expect(events.some((event: any) => event?.name === "Unresolved"
          && event.args.key === key && event.args.digest === digest)).to.equal(true);
        results.push({ bytes: size, state, minimumTransactionGas: high,
          pipeAttempted: callIndex >= 0, gasAfterPipe: afterCall ? Number(afterCall.gas) : null,
          gasUsed: Number(receipt.gasUsed) });
      }
    }
    mkdirSync(".npm-cache", { recursive: true });
    writeFileSync(".npm-cache/portal-gas-results.json", JSON.stringify(results, null, 2) + "\n");
    console.table(results);
  });

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
