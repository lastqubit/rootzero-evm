import { expect } from "chai";
import { ethers } from "ethers";
import { deploy } from "./helpers/setup.js";
import { concat, encodeBlock } from "./helpers/blocks.js";

import { fixedLayouts } from "./helpers/encoder-outputs.js";

describe("Execution encoder block types", function () {
  this.timeout(120_000);
  it("encodes every fixed type independently and preserves full-width fields through growth", async () => {
    const helper = await deploy("TestEncoderOutputs");
    const fields = [ethers.MaxUint256, 1n << 255n, 0n, 123n, 456n].map(n => ethers.toBeHex(n, 32));
    for (const [kind, layout] of fixedLayouts.entries()) {
      const key = ethers.id("#" + layout.name[0].toLowerCase() + layout.name.slice(1)).slice(0, 10);
      const block = encodeBlock(key, concat(...fields.slice(0, layout.words)));
      for (const count of [0, 1, 2, 4]) for (const capacity of [0, ethers.dataLength(block) * count]) {
        for (const previous of [false, true]) {
          const [, output] = await helper.fixedBlocks(kind, fields, count, capacity, previous);
          expect(output, layout.name).eq(concat(...Array(count).fill(block)));
        }
      }
    }
  });
  it("writes memory and calldata payload blocks including empty and unaligned payloads", async () => {
    const helper = await deploy("TestEncoderOutputs");
    for (const [kind, name] of ["list", "bytes", "string"].entries()) for (const size of [0, 1, 31, 32, 65]) {
      const data = "0x" + "ab".repeat(size), block = encodeBlock(ethers.id("#" + name).slice(0, 10), data);
      for (const capacity of [0, 4 * ethers.dataLength(block)]) for (const calldata of [false, true]) {
        expect(await helper.payloads(kind, data, 4, capacity, calldata)).eq(concat(...Array(4).fill(block)));
      }
    }
  });
});
