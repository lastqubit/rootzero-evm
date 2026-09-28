import { expect } from "chai";
import { ethers } from "ethers";
import { deploy } from "./helpers/setup.js";
import { concat } from "./helpers/blocks.js";

describe("Eager encoder primitives", function () {
  for (const name of ["EagerRelative", "EagerAbsolute"]) {
    it(`${name} preserves initialized bytes, metadata, scratch and padding through growth`, async () => {
      const helper = await deploy(`Test${name}Encoder`);
      for (const count of [0, 1, 2, 4, 16]) for (const capacity of [0, 1, 17, 31, 32, 68, 272]) {
        const [metadata, output, padding] = await helper.inspect(capacity, count);
        expect(metadata).eq(0xabcdefn);
        expect(output).eq(concat(...Array.from({ length: count }, (_, j) => "0x0102030400000001" + ethers.toBeHex(j, 1).slice(2) + "0506070800000000")));
        expect(padding).eq(ethers.ZeroHash);
      }
    });
    it(`${name} rejects capacity and reservation overflow`, async () => {
      const helper = await deploy(`Test${name}Encoder`);
      for (const [capacity, size] of [[1n << 32n, 0n], [0n, 1n << 32n], [0n, ethers.MaxUint256]]) {
        let failed = false;
        try { await helper.overflow(capacity, size); } catch { failed = true; }
        expect(failed).eq(true);
      }
    });
  }
});
