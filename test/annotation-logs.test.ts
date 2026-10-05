import { expect } from "chai";
import { ethers } from "ethers";
import { deploy, getSigner, hostId, commandId } from "./helpers/setup.js";
import { encodeAnnotationBlock, encodeLabelBlock, encodeSchemaBlock, encodeContextBlock, encodeInputBlock, Keys, exactSpec } from "./helpers/blocks.js";
import { HostAnnotate, decodeAnnotationLog } from "./helpers/annotation-logs.js";
import "./helpers/matchers.js";

describe("Annotation block logs", () => {
  it("preserves full-width entities and exact memory payloads without ABI topics or padding", async () => {
    const helper = await deploy("TestAnnotationLogs");
    for (const entity of [0n, ethers.MaxUint256]) for (const length of [0, 1, 31, 32, 33, 97]) {
      const data = "0x" + "ab".repeat(length);
      expect(await helper.publish.staticCall(entity, data)).eq(data);
      const receipt = await (await helper.publish(entity, data)).wait();
      expect(receipt.logs.map((log: any) => ({ topics: log.topics, data: log.data }))).deep.eq([
        { topics: [], data: ethers.concat([ethers.toBeHex(HostAnnotate, 32), encodeAnnotationBlock(entity, data)]) },
      ]);
    }
  });

  it("publishes constructor metadata without Annotation ABI discovery and logs admin input once", async () => {
    const host = await deploy("TestHost", await hostId(await (await getSigner()).getAddress()));
    const deployment = await host.deploymentTransaction().wait();
    expect(host.interface.getEvent("Annotation")).eq(null);
    expect(host.interface.getEvent("EventAbi")).eq(null);
    expect(deployment.logs.flatMap((log: any) => decodeAnnotationLog(log)).length).greaterThan(0);
    const id = await commandId("annotate(bytes)", host, 2n);
    const label = encodeLabelBlock(ethers.ZeroHash, "subject");
    const schema = encodeSchemaBlock(exactSpec(Keys.Balance, 64), "balance: { bytes32 asset, uint amount }");
    const batch = ethers.concat([encodeAnnotationBlock(0n, label), encodeAnnotationBlock(ethers.MaxUint256, schema)]);
    for (const input of ["0x", batch]) {
      const receipt = await (await host.annotate(encodeContextBlock(await host.getAdminAccount(), "0x", input))).wait();
      expect(receipt.logs.map((log: any) => ({ topics: log.topics, data: log.data }))).deep.eq([
        { topics: [], data: ethers.concat([ethers.toBeHex(id, 32), encodeInputBlock(input)]) },
      ]);
      expect(receipt.logs.flatMap((log: any) => decodeAnnotationLog(log, id))).deep.eq(input === "0x" ? [] : [
        { entity: 0n, data: label }, { entity: ethers.MaxUint256, data: schema },
      ]);
    }
    const malformed = ethers.concat([batch, "0x01"]);
    await expect(host.annotate(encodeContextBlock(await host.getAdminAccount(), "0x", malformed)))
      .revertedWithCustomError(host, "InvalidBlock");
  });
  it("validates every envelope and child while leaving annotation payloads opaque", async () => {
    const host = await deploy("TestHost", await hostId(await (await getSigner()).getAddress()));
    const account = await host.getAdminAccount();
    const good = encodeAnnotationBlock(1n, "0xab");
    await host.annotate(encodeContextBlock(account, "0x", good));
    const wrongChild = good.slice(0, 82) + Keys.Input.slice(2) + good.slice(90);
    for (const [bad, error] of [
      [encodeLabelBlock(ethers.ZeroHash, "wrong parent"), "InvalidBlock"],
      [wrongChild, "InvalidBlock"],
      [good.slice(0, -2), "OutOfBounds"],
    ]) {
      await expect(host.annotate(encodeContextBlock(account, "0x", ethers.concat([good, bad]))))
        .revertedWithCustomError(host, error);
    }
    await expect(host.annotate(encodeContextBlock(account, good, good)))
      .revertedWithCustomError(host, "UnconsumedData");
  });

});
