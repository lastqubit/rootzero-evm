import { expect } from "chai";
import { ethers } from "ethers";
import { deploy } from "./helpers/setup.js";
import { Keys, exactSpec, encodeBlock } from "./helpers/blocks.js";

describe("Envelope block logs", () => {
  it("defines the canonical fixed four-word schema", async () => {
    const helper = await deploy("TestEnvelopeLogs");
    const spec = exactSpec(Keys.Envelope, 128);
    expect(Array.from(await helper.catalog())).deep.eq([
      ethers.id("#envelope").slice(0, 10), spec, 136n, spec >> 192n,
      "uint portal, uint resources, bytes32 key, bytes32 digest",
    ]);
  });

  it("preserves distinct and full-width fields with exact topic-free logging", async () => {
    const helper = await deploy("TestEnvelopeLogs");
    for (const values of [
      [0n, 0n, ethers.ZeroHash, ethers.ZeroHash],
      [123n, 456n, ethers.id("transport key"), ethers.keccak256("0xabcdef")],
      [ethers.MaxUint256, ethers.MaxUint256, ethers.toBeHex(ethers.MaxUint256, 32), ethers.toBeHex(ethers.MaxUint256, 32)],
    ] as const) {
      const [portal, resources, key, digest] = values;
      const block = encodeBlock(Keys.Envelope, ethers.concat([
        ethers.toBeHex(portal, 32), ethers.toBeHex(resources, 32), key, digest,
      ]));
      for (const codes of [0n, 0x20000001n | (96n << 32n), 0x20000002n | (97n << 32n), ethers.MaxUint256]) {
        expect(await helper.publish.staticCall(...values, codes)).eq(block);
        const receipt = await (await helper.publish(...values, codes)).wait();
        expect(receipt.logs.map((log: any) => ({ topics: log.topics, data: log.data }))).deep.eq([
          { topics: [], data: ethers.concat([ethers.toBeHex(codes, 32), block]) },
        ]);
      }
    }
  });
});
