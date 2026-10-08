import { expect } from "chai";
import { ethers } from "ethers";
import { deploy, getSigner, hostId } from "./helpers/setup.js";
import { decodeMetadataLog } from "./helpers/metadata-logs.js";
import "./helpers/matchers.js";

describe("Metadata records", () => {
  it("preserves full-width entities and exact memory payloads without ABI topics or padding", async () => {
    const helper = await deploy("TestAnnotationLogs");
    for (const entity of [0n, ethers.MaxUint256]) for (const length of [0, 1, 31, 32, 33, 97]) {
      const data = "0x" + "ab".repeat(length);
      expect(await helper.publish.staticCall(entity, data)).eq(data);
      const receipt = await (await helper.publish(entity, data)).wait();
      expect(receipt.logs.map((log: any) => ({ topics: log.topics, data: log.data }))).deep.eq([
        { topics: [], data: ethers.concat(["0x03", ethers.toBeHex(entity, 32), data]) },
      ]);
    }
  });

  it("keeps schema metadata and removes the admin annotation endpoint", async () => {
    const host = await deploy("TestHost", await hostId(await (await getSigner()).getAddress()));
    const receipt = await host.deploymentTransaction().wait();
    expect(host.interface.getFunction("annotate(bytes)")).eq(null);
    expect(receipt.logs.flatMap((log: any) => decodeMetadataLog(log)).length).greaterThan(0);
  });
});
