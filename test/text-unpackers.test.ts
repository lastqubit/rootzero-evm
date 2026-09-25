import { expect } from "chai";
import { ethers } from "ethers";
import { deploy } from "./helpers/setup.js";
import "./helpers/matchers.js";
import { encodeStringBlock, encodeLabelBlock, encodeSchemaBlock } from "./helpers/blocks.js";

const encoders = [
  encodeStringBlock,
  (text: string) => encodeLabelBlock(ethers.toBeHex(123, 32), text),
  (text: string) => encodeSchemaBlock(123n, text),
];

describe("Text unpacker bounds before memory copies", function () {
  for (const execution of [false, true]) {
    for (const [kind, name] of ["STRING", "LABEL", "SCHEMA"].entries()) {
      describe(`${execution ? "Execution" : "Cursor"} ${name}`, function () {
        let helper: any;
        before(async () => { helper = await deploy("TestTextUnpackers"); });

        it("returns exact text and consumes only the decoded block", async () => {
          for (const text of ["", "schema: string value", "å🙂".repeat(17)]) {
            const block = encoders[kind](text);
            const size = ethers.dataLength(block);
            for (const data of [block, ethers.concat([block, encoders[kind]("next")])]) {
              expect(await helper.decode(kind, execution, data, ethers.dataLength(data)))
                .to.deep.equal([kind === 0 ? 0n : 123n, text, BigInt(size)]);
            }
          }
        });

        it("returns exact OutOfBounds for every truncated text body", async () => {
          const block = encoders[kind]("x".repeat(65));
          const headerEnd = kind === 0 ? 8 : 48;
          for (let length = headerEnd; length < ethers.dataLength(block); length++) {
            // Test both physical truncation and a shorter logical source.
            for (const data of [ethers.dataSlice(block, 0, length), block]) {
              await expect(helper.decode(kind, execution, data, length))
                .to.be.revertedWithCustomError(helper, "OutOfBounds");
            }
          }
        });

        it("keeps header errors ahead of source bounds errors", async () => {
          const block = encoders[kind]("text");
          for (const offset of kind === 0 ? [0] : [0, 40, 47]) {
            const bad = ethers.getBytes(block);
            bad[offset] ^= 0xff;
            for (const length of [1, bad.length]) {
              await expect(helper.decode(kind, execution, bad, length))
                .to.be.revertedWithCustomError(helper, "InvalidBlock");
            }
          }
        });
      });
    }
  }
});
