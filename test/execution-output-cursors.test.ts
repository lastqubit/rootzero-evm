import { expect } from "chai";
import { ethers } from "ethers";
import { deploy } from "./helpers/setup.js";
import "./helpers/matchers.js";
import { encodeBlock, encodeStepBlock, encodeCallBlock, encodeDispatchBlock,
  encodeRelayBlock, encodeContextBlock, encodeRecoverBlock, exactSpec, Keys } from "./helpers/blocks.js";

describe("Execution output payload cursors", () => {
  const word = ethers.toBeHex(33, 32);
  const layouts = [
    (a: string, b: string) => encodeBlock(Keys.Bytes, a),
    (a: string, b: string) => encodeBlock(Keys.List, a),
    (a: string, b: string) => encodeBlock(Keys.Bytes, a),
    (a: string, b: string) => encodeBlock(Keys.String, a),
    (a: string, b: string) => encodeStepBlock(11n, 22n, a),
    (a: string, b: string) => encodeCallBlock(11n, 22n, a),
    (a: string, b: string) => encodeDispatchBlock(11n, 22n, a),
    encodeRelayBlock,
    (a: string, b: string) => encodeContextBlock(word, a, b),
    (a: string, b: string) => encodeRecoverBlock(11n, 22n, word, a),
    (a: string, b: string) => encodeBlock(Keys.Label, ethers.concat([word, encodeBlock(Keys.String, a)])),
    (a: string, b: string) => encodeBlock(Keys.Schema, ethers.concat([ethers.toBeHex(11, 32), encodeBlock(Keys.String, a)])),
  ];

  it("wraps only the selected ranges and preserves source cursors across repeated writes and growth", async () => {
    const helper = await deploy("TestExecutionOutputCursors");
    const prefix = encodeBlock(Keys.Account, ethers.toBeHex(77, 32));
    for (const [kind, layout] of layouts.entries()) for (const size of [0, 1, 31, 32, 33, 65]) for (const whole of [false, true]) {
      const a = "0x" + "ab".repeat(size), b = "0x" + "cd".repeat(size % 3);
      const key = kind === 1 ? Keys.List : kind === 3 || kind >= 10 ? Keys.String
        : kind === 4 || kind === 7 ? Keys.Input : kind === 8 ? Keys.State : Keys.Bytes;
      const selectedA = whole ? encodeBlock(key, a) : a;
      const selectedB = whole ? encodeBlock(kind === 8 ? Keys.Input : Keys.Bytes, b) : b;
      const sourceA = ethers.concat(["0xfe", selectedA, "0xef"]), sourceB = ethers.concat(["0xfe", selectedB, "0xef"]);
      const expected = ethers.concat([prefix, layout(a, b), layout(a, b)]);
      for (const capacity of [0, ethers.dataLength(expected)]) {
        const result = await helper.encode(kind, sourceA, sourceB, 2, capacity, whole);
        expect(result.output).eq(expected);
        expect(result.aCur).eq((result.baseA + 1n) | ((result.baseA + BigInt(ethers.dataLength(selectedA) + 1)) << 32n));
        expect(result.bCur).eq((result.baseB + 1n) | ((result.baseB + BigInt(ethers.dataLength(selectedB) + 1)) << 32n));
      }
    }
  });

  it("passes decoded child cursors directly into output without duplicating headers", async () => {
    const helper = await deploy("TestExecutionOutputCursors");
    for (const [state, input] of [["0x", "0x"], ["0x010203", "0x"], ["0x", "0x1234"], ["0xaabb", "0xccdd"]]) {
      const source = encodeContextBlock(word, state, input);
      for (const capacity of [0, ethers.dataLength(source)]) {
        expect(await helper.rewrapContext(source, capacity)).eq(source);
        expect(await helper.copyContext(source, capacity)).eq(source);
      }
    }
  });

  it("still enforces custom spec lengths against the selected payload", async () => {
    const helper = await deploy("TestExecutionOutputCursors");
    const spec = exactSpec(Keys.Bytes, 2);
    expect(await helper.custom(spec, "0xaabb")).eq(encodeBlock(Keys.Bytes, "0xaabb"));
    for (const source of ["0x", "0xaa", "0xaabbcc"]) {
      await expect(helper.custom(spec, source)).to.be.revertedWithCustomError(helper, "InvalidSpec");
    }
  });
});
