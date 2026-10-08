import { expect } from "chai";
import { ethers } from "ethers";
import { deploy, getSigner, hostId } from "./helpers/setup.js";
import { decodeEndpointLog } from "./helpers/endpoint-logs.js";
import { decodeIntroductionLog } from "./helpers/introduction-logs.js";
import { decodeMetadataLog } from "./helpers/metadata-logs.js";
import { decodeBlocks } from "./helpers/log-blocks.js";
import { Keys } from "./helpers/blocks.js";
import { Category, eventRecord, word } from "./helpers/event-records.js";

describe("Named discovery records", () => {
  it("appends exact name bytes without padding and preserves live and shared-empty memory", async () => {
    const helper = await deploy("TestNamedDiscovery");
    const account = ethers.id("account");
    for (const sharedEmpty of [false, true]) {
      for (const name of ["", "A", "a".repeat(31), "b".repeat(32), "c".repeat(33), "Räksmörgås 🚀", "x".repeat(257)]) {
        const expected = sharedEmpty ? "" : name;
        expect(await helper.publish.staticCall(ethers.MaxUint256, account, name, sharedEmpty)).eq(expected);
        const receipt = await (await helper.publish(ethers.MaxUint256, account, name, sharedEmpty)).wait();
        expect(receipt.logs.map((log: any) => [log.topics, log.data])).deep.eq([
          [[], eventRecord(Category.Endpoint, word(ethers.MaxUint256), word(1), word(2), word(3), ethers.hexlify(ethers.toUtf8Bytes(expected)))],
          [[], eventRecord(Category.Introduction, word(ethers.MaxUint256), account, word(4), ethers.hexlify(ethers.toUtf8Bytes(expected)))],
        ]);
        expect(decodeEndpointLog(receipt.logs[0])).deep.eq([ethers.MaxUint256, 1n, 2n, 3n, expected]);
        expect(decodeIntroductionLog(receipt.logs[1])).deep.eq({peer: ethers.MaxUint256, origin: account, blocknum: 4n, name: expected});
      }
    }
  });

  it("names the peer on its receiver and allows repeated names without changing identity", async () => {
    const root = await deploy("TestNamedHost", 0, "root");
    const rootReceipt = await root.deploymentTransaction().wait();
    expect(rootReceipt.logs.map(decodeIntroductionLog).filter(Boolean)).deep.eq([]);
    const hosts = await Promise.all([deploy("TestNamedHost", await root.host(), "same"), deploy("TestNamedHost", await root.host(), "same")]);
    expect(await hosts[0].host()).not.eq(await hosts[1].host());
    for (const host of hosts) {
      const receipt = await host.deploymentTransaction().wait();
      const log = receipt.logs.find((log: any) => decodeIntroductionLog(log) !== null);
      expect(log.address.toLowerCase()).eq((await root.getAddress()).toLowerCase());
      expect(decodeIntroductionLog(log)?.peer).eq(await host.host());
      expect(decodeIntroductionLog(log)?.name).eq("same");
      const later = await (await host.announce(await root.host(), "new discovery hint")).wait();
      expect(decodeIntroductionLog(later.logs[0])?.peer).eq(await host.host());
      expect(decodeIntroductionLog(later.logs[0])?.name).eq("new discovery hint");
    }
    const eoaHost = await deploy("TestNamedHost", await hostId(await (await getSigner()).getAddress()), "unannounced");
    expect((await eoaHost.deploymentTransaction().wait()).logs.map(decodeIntroductionLog).filter(Boolean)).deep.eq([]);
  });

  it("keeps endpoint names and schemas without LABEL metadata or an annotate command", async () => {
    const host = await deploy("TestHost", 0);
    const receipt = await host.deploymentTransaction().wait();
    const endpoints = receipt.logs.map(decodeEndpointLog).filter(Boolean);
    expect(endpoints.length).greaterThan(0);
    for (const endpoint of endpoints) {
      const name = endpoint[4];
      expect(name.length).greaterThan(0);
      expect(ethers.toBeHex((endpoint[0] >> 160n) & 0xffffffffn, 4)).eq(ethers.id(`${name}(bytes)`).slice(0, 10));
    }
    const metadata = receipt.logs.flatMap(decodeMetadataLog).flatMap((value: any) => decodeBlocks(value.data));
    expect(metadata.some((block: any) => block.key === Keys.Schema)).eq(true);
    expect(metadata.some((block: any) => block.key === Keys.Label)).eq(false);
    expect(host.interface.getFunction("annotate(bytes)")).eq(null);
  });
});
