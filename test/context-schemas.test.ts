import { expect } from "chai";
import { ethers } from "ethers";
import { deploy } from "./helpers/setup.js";
import { Keys, concat, encodeBlock, encodeBytesBlock, encodeStateBlock, encodeInputBlock,
  encodeBalanceBlock, encodeAssetAmountBlock, encodeContextBlock, encodeStepBlock, encodeRelayBlock } from "./helpers/blocks.js";
async function expectRevert(call: Promise<unknown>) {
  await call.then(() => expect.fail("Expected an EVM revert"), (error: any) => {
    expect(error.data).to.be.a("string");
  });
}

describe("Typed State and Input containers", () => {
  const account = ethers.id("account");
  const asset = ethers.id("asset");
  const state = encodeBalanceBlock(asset, ethers.MaxUint256);
  const input = encodeAssetAmountBlock(asset, 7n);

  it("publishes canonical keys and unbounded specs", async () => {
    const helper = await deploy("TestContextSchemas");
    const catalog = await helper.catalog();
    expect(Array.from(catalog)).deep.eq([
      Keys.State, Keys.Input, BigInt(Keys.State), BigInt(Keys.Input),
      (BigInt(Keys.State) << 224n) | (128n << 136n),
      (BigInt(Keys.Input) << 224n) | (128n << 136n),
      "bytes32 account, #state, #input",
    ]);
  });

  it("round-trips typed contexts from memory and calldata, including empty streams", async () => {
    const helper = await deploy("TestContextSchemas");
    for (const a of ["0x", state]) for (const b of ["0x", input]) {
      const expected = encodeContextBlock(account, a, b);
      expect(ethers.dataSlice(expected, 40, 44)).eq(Keys.State);
      expect(ethers.dataSlice(expected, 48 + ethers.dataLength(a), 52 + ethers.dataLength(a))).eq(Keys.Input);
      expect(ethers.dataLength(expected)).eq(56 + ethers.dataLength(a) + ethers.dataLength(b));
      for (const memory of [false, true]) expect(await helper.encode(account, a, b, memory)).eq(expected);
      for (const execution of [false, true])
        expect(Array.from(await helper.decode(expected, execution))).deep.eq([account, a, b]);
    }
  });

  it("rejects old, swapped, duplicate and malformed Context children", async () => {
    const helper = await deploy("TestContextSchemas");
    const bodies = [
      concat(encodeBytesBlock(state), encodeBytesBlock(input)),
      concat(encodeStateBlock(state), encodeBytesBlock(input)),
      concat(encodeBytesBlock(state), encodeInputBlock(input)),
      concat(encodeInputBlock(state), encodeStateBlock(input)),
      concat(encodeStateBlock(state), encodeStateBlock(input)),
      concat(encodeInputBlock(state), encodeInputBlock(input)),
      encodeStateBlock(state),
      concat(encodeStateBlock(state), Keys.Input, "0xffffffff"),
      concat(Keys.State, "0xffffffff", encodeInputBlock(input)),
      concat(encodeStateBlock(state), encodeInputBlock(input), encodeInputBlock("0x")),
    ];
    for (const body of bodies) for (const execution of [false, true])
      await expectRevert(helper.decode(encodeBlock(Keys.Context, concat(account, body)), execution));
    const valid = encodeContextBlock(account, state, input);
    for (const length of [0, 7, 39, 47, ethers.dataLength(valid) - 1])
      for (const execution of [false, true])
        await expectRevert(helper.decode(ethers.dataSlice(valid, 0, length), execution));
  });

  it("requires Input in Step and Relay while Relay steps remain Bytes", async () => {
    const helper = await deploy("TestCursorHelper");
    const step = encodeStepBlock(123n, 9n, input);
    expect(Array.from(await helper.testUnpackStep(step))).deep.eq([123n, 9n, input, BigInt(ethers.dataLength(step))]);
    const relay = encodeRelayBlock(input, step);
    expect(Array.from(await helper.testUnpackRelayStreams(relay))).deep.eq([input, step, BigInt(ethers.dataLength(relay))]);
    for (const wrong of [encodeBytesBlock(input), encodeStateBlock(input)]) {
      const oldStep = encodeBlock(Keys.Step, concat(ethers.toBeHex(123n, 32), ethers.toBeHex(9n, 32), wrong));
      await expectRevert(helper.testUnpackStep(oldStep));
      await expectRevert(helper.testUnpackRelayStreams(encodeBlock(Keys.Relay, concat(wrong, encodeBytesBlock(step)))));
    }
    await expectRevert(helper.testUnpackRelayStreams(encodeBlock(Keys.Relay, concat(encodeInputBlock(input), encodeInputBlock(step)))));
  });
});
