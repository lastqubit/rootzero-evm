import { expect } from "chai";
import { ethers } from "ethers";
import { deploy, getSigner, hostId } from "./helpers/setup.js";
import { concat, encodeNodeBlock, encodeStepBlock } from "./helpers/blocks.js";
import "./helpers/matchers.js";

describe("ExecuteAuthorize", () => {
  let host: Awaited<ReturnType<typeof deploy>>;
  let admin: string;
  let command: bigint;
  let node: bigint;

  beforeEach(async () => {
    host = await deploy("TestExecuteAuthorize", 0n);
    admin = await host.adminAccount();
    command = await host.commandId();
    node = await hostId(await (await getSigner(4)).getAddress());
  });

  it("authorizes nodes without allowlisting the local command", async () => {
    const second = await hostId(await (await getSigner(5)).getAddress());
    expect(await host.isAuthorized(command)).to.equal(false);
    await expect(host.testPipe(admin, "0x", encodeStepBlock(command, 0n,
      concat(encodeNodeBlock(node), encodeNodeBlock(second)))))
      .to.emit(host, "Node").withArgs(await host.host(), node, true);
    expect(await host.isAuthorized(node)).to.equal(true);
    expect(await host.isAuthorized(second)).to.equal(true);
  });

  it("accepts an empty node stream", async () => {
    await host.testPipe(admin, "0x", encodeStepBlock(command, 0n, "0x"));
  });

  it("rejects non-admin accounts", async () => {
    await expect(host.testPipe(ethers.ZeroHash, "0x",
      encodeStepBlock(command, 0n, encodeNodeBlock(node))))
      .to.be.revertedWithCustomError(host, "AccessDenied");
  });

  it("rejects internal execution on externally managed hosts", async () => {
    const managed = await deploy("TestExecuteAuthorize",
      await hostId(await (await getSigner(0)).getAddress()));
    await expect(managed.testPipe(await managed.adminAccount(), "0x",
      encodeStepBlock(await managed.commandId(), 0n, encodeNodeBlock(node))))
      .to.be.revertedWithCustomError(managed, "AccessDenied");
  });

  it("rejects nonempty state", async () => {
    await expect(host.testPipe(admin, "0x01", encodeStepBlock(command, 0n, "0x")))
      .to.be.revertedWithCustomError(host, "UnexpectedState");
  });

  it("returns assigned value to the pipeline budget", async () => {
    const steps = concat(
      encodeStepBlock(command, 3n, encodeNodeBlock(node)),
      encodeStepBlock(command, 5n, "0x"),
    );
    expect(await host.testPipe.staticCall(admin, "0x", steps, { value: 7n })).to.equal(7n);
    await host.testPipe(admin, "0x", steps, { value: 7n });
    expect(await host.isAuthorized(node)).to.equal(true);
  });

  it("rejects malformed streams atomically", async () => {
    const wrongHeader = "0x00000000" + encodeNodeBlock(node).slice(10);
    for (const [malformed, error] of [
      ["0x01", "InvalidBlock"],
      [wrongHeader, "InvalidBlock"],
      [encodeNodeBlock(1n), "InvalidId"],
    ]) {
      await expect(host.testPipe(admin, "0x", encodeStepBlock(command, 0n,
        concat(encodeNodeBlock(node), malformed)))).to.be.revertedWithCustomError(host, error);
      expect(await host.isAuthorized(node)).to.equal(false);
    }
  });
});
