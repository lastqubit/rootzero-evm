import { decodeIntroductionLog } from "./helpers/introduction-logs.js";
import { expect } from "chai";
import { ethers } from "ethers";
import { commandId, deploy, getSigner, hostId, portId } from "./helpers/setup.js";
import "./helpers/matchers.js";

describe("UpstreamPort", () => {
  let commander: string;
  let target: Awaited<ReturnType<typeof deploy>>;

  before(async () => {
    commander = await (await getSigner(0)).getAddress();
    target = await deploy("TestUpstreamTarget", await hostId(commander));
  });

  function introductionsTo(receipt: ethers.TransactionReceipt, receiver: string) {
    return receipt.logs.filter(log => log.address.toLowerCase() === receiver.toLowerCase())
      .map(decodeIntroductionLog).filter(value => value !== null);
  }

  it("introduces itself to the upstream host on deployment", async () => {
    for (const name of ["TestUpstreamCommandHost", "TestUpstreamHost"]) {
      const host = await deploy(name, await hostId(commander), await portId("portEcho(bytes)", target, 1n));
      const receipt = await host.deploymentTransaction()!.wait();
      const introductions = introductionsTo(receipt!, await target.getAddress());
      expect(introductions.map(value => [value!.peer, value!.name])).deep.eq([[await hostId(host), "upstream"]]);
    }
  });

  it("introduces only once when the upstream is the commander", async () => {
    const host = await deploy("TestUpstreamCommandHost", await hostId(target), await portId("portEcho(bytes)", target, 1n));
    const receipt = await host.deploymentTransaction()!.wait();
    const introductions = introductionsTo(receipt!, await target.getAddress());
    expect(introductions.map(value => value!.name)).deep.eq(["TestUpstreamCommandHost"]);
  });

  it("calls the upstream port with and without value", async () => {
    const host = await deploy("TestUpstreamCommandHost", await hostId(commander), await portId("portEcho(bytes)", target, 1n));

    expect(await host.callPaid.staticCall("0x1234", false, { value: 7n })).deep.eq(["0x1234", 7n]);
    expect(await host.callFree.staticCall("0xabcd", false)).deep.eq(["0xabcd", 0n]);
  });

  it("enforces empty output when expectEmpty is set", async () => {
    const host = await deploy("TestUpstreamCommandHost", await hostId(commander), await portId("portEcho(bytes)", target, 1n));

    expect(await host.callPaid.staticCall("0x", true, { value: 3n })).deep.eq(["0x", 3n]);
    expect(await host.callFree.staticCall("0x", true)).deep.eq(["0x", 0n]);
    for (const call of [
      () => host.callPaid.staticCall("0x12", true, { value: 3n }),
      () => host.callFree.staticCall("0x12", true),
    ]) {
      let failure: string | undefined;
      try { await call(); }
      catch (error: any) { failure = error.data ?? error.info?.error?.data; }
      expect(failure).eq("0x");
    }
  });

  it("reverts FailedCall with the upstream's revert data", async () => {
    const port = await portId("portFail(bytes)", target);
    const host = await deploy("TestUpstreamCommandHost", await hostId(commander), port);
    const selector = target.interface.getFunction("portFail")!.selector;
    const reason = target.interface.encodeErrorResult("TestUpstreamFailed", ["0x99"]);
    const errors = new ethers.Interface(["error FailedCall(address addr, bytes4 selector, bytes err)"]);

    let failure: string | undefined;
    try { await host.callFree.staticCall("0x99", false); }
    catch (error: any) { failure = error.data ?? error.info?.error?.data; }
    expect(failure).eq(errors.encodeErrorResult("FailedCall", [await target.getAddress(), selector, reason]));
  });

  it("rejects IDs that are not local port IDs", async () => {
    for (const id of [
      await hostId(target),
      await commandId("portEcho(bytes)", target),
      await portId("portEcho(bytes)", ethers.ZeroAddress),
    ]) {
      let rejected = false;
      try {
        await deploy("TestUpstreamCommandHost", await hostId(commander), id);
      } catch {
        rejected = true;
      }
      expect(rejected).to.equal(true);
    }
  });

  it("rejects an upstream that does not accept introductions", async () => {
    const plain = await deploy("TestExecuteTarget");
    let rejected = false;
    try {
      await deploy("TestUpstreamCommandHost", await hostId(commander), await portId("portEcho(bytes)", plain));
    } catch {
      rejected = true;
    }
    expect(rejected).to.equal(true);
  });
});
