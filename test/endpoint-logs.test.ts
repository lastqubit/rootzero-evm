import { expect } from "chai";
import { ethers } from "ethers";
import { deploy } from "./helpers/setup.js";
import { exactSpec, encodeBlock } from "./helpers/blocks.js";
import { EndpointKey, decodeEndpointLog } from "./helpers/endpoint-logs.js";

describe("Endpoint category logs", () => {
  it("publishes the canonical schema and preserves four full-width fields", async () => {
    const helper = await deploy("TestEndpointLogs");
    const spec = exactSpec(EndpointKey, 128);
    expect(Array.from(await helper.catalog())).deep.eq([spec, 136n, spec >> 192n, "uint id, uint state, uint input, uint output"]);
    for (const values of [[0n, 0n, 0n, 0n], [ethers.MaxUint256, 1n << 255n, ethers.MaxUint256, 123n]]) {
      const block = encodeBlock(EndpointKey, ethers.concat(values.map(v => ethers.toBeHex(v, 32))));
      expect(await helper.publish.staticCall(...values)).eq(block);
      const receipt = await (await helper.publish(...values)).wait();
      expect(receipt.logs.length).eq(1);
      expect(receipt.logs[0].topics).deep.eq([]);
      expect(receipt.logs[0].data).eq(ethers.concat(["0x05", ethers.dataSlice(block, 8)]));
      expect(decodeEndpointLog(receipt.logs[0])).deep.eq([...values, ""]);
    }
  });

  it("discovers all endpoint families without an Endpoint ABI announcement", async () => {
    const helper = await deploy("TestEndpointRunners", 7);
    const receipt = await helper.deploymentTransaction().wait();
    const endpoints = receipt.logs.map(decodeEndpointLog).filter((value: ReturnType<typeof decodeEndpointLog>) => value !== null);
    expect(endpoints.length).eq(7);
    expect(helper.interface.getEvent("Endpoint")).eq(null);
    expect(helper.interface.getEvent("EventAbi")).eq(null);
    const ids = await Promise.all(Array.from({ length: 7 }, (_, i) => helper.ids(i)));
    expect(endpoints.map((value: NonNullable<ReturnType<typeof decodeEndpointLog>>) => value[0]).sort()).deep.eq(ids.sort());
  });
});
