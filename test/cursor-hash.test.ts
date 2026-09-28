import { expect } from "chai";
import { ethers } from "ethers";
import { deploy } from "./helpers/setup.js";

describe("CursorBlocks hash", () => {
  it("returns the remaining cursor length independently of metadata", async () => {
    const helper = await deploy("CursorLengthCurrent");
    for (const [start, end] of [[0n, 0n], [1n, 1n], [7n, 105n], [0n, 0xffffffffn]]) {
      for (const metadata of [0n, ethers.MaxUint256 & ~0xffffffffffffffffn]) {
        expect(await helper.length(start | (end << 32n) | metadata)).eq(end - start);
      }
    }
  });

  it("hashes exactly the selected range without allocation or damage to live memory", async () => {
    const helper = await deploy("CursorHashCurrent");
    const source = ethers.hexlify(Uint8Array.from({ length: 1100 }, (_, i) => i % 251));
    const guardHash = ethers.keccak256(ethers.concat([ethers.toBeHex(123, 32), ethers.toBeHex(456, 32)]));
    for (const start of [0, 1, 7, 32]) {
      for (const size of [0, 1, 3, 31, 32, 33, 63, 64, 65, 256, 1024]) {
        for (const metadata of [0n, ethers.MaxUint256]) {
          const r = await helper.measure(source, start, start + size, metadata);
          expect(r.digest).eq(ethers.keccak256(ethers.dataSlice(source, start, start + size)));
          expect(r.allocated).eq(0n);
          expect(r.guardHash).eq(guardHash);
          expect(r.zeroSlot).eq(0n);
        }
      }
    }
    expect((await helper.measure("0x", 0, 0, 0)).digest).eq(ethers.keccak256("0x"));
  });
});
