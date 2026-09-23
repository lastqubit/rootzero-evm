import { expect } from "chai";
import { ethers } from "ethers";
import { deploy, getSigner } from "./helpers/setup.js";
import { concat, encodeAmountBlock, encodeBalanceBlock, encodeContextBlock } from "./helpers/blocks.js";
import "./helpers/matchers.js";

describe("Execution runners", () => {
  const asset = ethers.zeroPadValue("0x11", 32);
  const account = ethers.zeroPadValue("0x22", 32);
  let helper: Awaited<ReturnType<typeof deploy>>;

  beforeEach(async () => { helper = await deploy("TestExecutionCallbacks"); });

  it("passes a contract function through a runner and library with shared execution memory", async () => {
    const context = encodeContextBlock(account, "0x", concat(
      encodeAmountBlock(asset, 3n), encodeAmountBlock(asset, 7n),
    ));
    const result = await helper.execute.staticCall(context, { value: 5n });
    expect(Array.from(result)).to.deep.equal(Array.from(
      await helper.executeManual.staticCall(context, { value: 5n }),
    ));
    expect(Array.from(result)).to.deep.equal([
      concat(encodeAmountBlock(asset, 6n), encodeAmountBlock(asset, 14n)), 5n,
    ]);
    await (await helper.execute(context, { value: 5n })).wait();
    expect(await helper.processed()).to.equal(2n);
    expect(await helper.lastAccount()).to.equal(account);
    expect(await helper.lastCaller()).to.equal(await (await getSigner()).getAddress());
  });

  it("closes an empty batch without invoking the callback", async () => {
    const context = encodeContextBlock(account, "0x", "0x");
    expect(Array.from(await helper.execute.staticCall(context, { value: 5n })))
      .to.deep.equal(["0x", 5n]);
    await (await helper.execute(context)).wait();
    expect(await helper.processed()).to.equal(0n);
  });

  it("propagates callback reverts and rolls back preceding items", async () => {
    const context = encodeContextBlock(account, "0x", concat(
      encodeAmountBlock(asset, 3n), encodeAmountBlock(asset, 13n),
    ));
    await expect(helper.execute(context, { gasLimit: 1_000_000 }))
      .to.be.revertedWithCustomError(helper, "RejectedRequest");
    expect(await helper.processed()).to.equal(0n);
    expect(await helper.lastAccount()).to.equal(ethers.ZeroHash);
  });

  it("iterates state-only batches and returns the callback's remaining budget", async () => {
    const context = encodeContextBlock(account, concat(
      encodeBalanceBlock(asset, 3n), encodeBalanceBlock(asset, 7n),
    ), "0x");
    expect(Array.from(await helper.executeState.staticCall(context, { value: 5n })))
      .to.deep.equal([
        concat(encodeAmountBlock(asset, 3n), encodeAmountBlock(asset, 7n)), 3n,
      ]);
    await expect(helper.executeState.staticCall(context, { value: 1n }))
      .to.be.revertedWithCustomError(helper, "InsufficientValue");
  });

  it("rejects malformed contexts before invoking the callback", async () => {
    const context = encodeContextBlock(account, "0x", encodeAmountBlock(asset, 3n));
    for (const invalid of [
      "0x", "0x1234", encodeAmountBlock(asset, 3n),
      ethers.dataSlice(context, 0, ethers.dataLength(context) - 1),
      concat(context, "0x00"), concat(context, context),
    ]) {
      await expect(helper.execute.staticCall(invalid)).to.be.revertedWithCustomError(helper, "InvalidBlock");
      await expect(helper.executeOnce.staticCall(invalid)).to.be.revertedWithCustomError(helper, "InvalidBlock");
      await expect(helper.executeManual.staticCall(invalid)).to.be.revertedWithCustomError(helper, "InvalidBlock");
    }
    expect(await helper.processed()).to.equal(0n);
  });

  it("does not silently finish when input is exhausted but state remains", async () => {
    const context = encodeContextBlock(account, encodeBalanceBlock(asset, 7n), encodeAmountBlock(asset, 3n));
    await expect(helper.execute(context, { gasLimit: 1_000_000 }))
      .to.be.revertedWithCustomError(helper, "OutOfBounds");
    expect(await helper.processed()).to.equal(0n);
  });

  it("runCommandOnce returns the callback output and credit after one invocation", async () => {
    const context = encodeContextBlock(account, "0x", encodeAmountBlock(asset, 3n));
    expect(Array.from(await helper.executeOnce.staticCall(context, { value: 5n })))
      .to.deep.equal([encodeAmountBlock(asset, 6n), 5n]);
    await (await helper.executeOnce(context)).wait();
    expect(await helper.processed()).to.equal(1n);
    expect(await helper.lastAccount()).to.equal(account);
    expect(await helper.lastCaller()).to.equal(await (await getSigner()).getAddress());
  });

  it("runCommandOnce invokes an empty-source callback and accounts for its budget use", async () => {
    const context = encodeContextBlock(account, "0x", "0x");
    expect(Array.from(await helper.executeOnceEmpty.staticCall(context, { value: 5n })))
      .to.deep.equal(["0x", 4n]);
    await (await helper.executeOnceEmpty(context, { value: 5n })).wait();
    expect(await helper.processed()).to.equal(1n);
    expect(await helper.lastAccount()).to.equal(account);
  });

  it("runCommandOnce lets the callback reject missing required input and propagates hook errors", async () => {
    await expect(helper.executeOnce(encodeContextBlock(account, "0x", "0x")))
      .to.be.revertedWithCustomError(helper, "OutOfBounds");
    await expect(helper.executeOnce(encodeContextBlock(account, "0x", encodeAmountBlock(asset, 13n))))
      .to.be.revertedWithCustomError(helper, "RejectedRequest");
    expect(await helper.processed()).to.equal(0n);
  });

  it("runCommandOnce rejects leftover input or state and rolls back the callback", async () => {
    const amount = encodeAmountBlock(asset, 3n);
    for (const context of [
      encodeContextBlock(account, "0x", concat(amount, amount)),
      encodeContextBlock(account, encodeBalanceBlock(asset, 7n), amount),
    ]) {
      await expect(helper.executeOnce(context, { gasLimit: 1_000_000 }))
        .to.be.revertedWithCustomError(helper, "UnconsumedData");
      expect(await helper.processed()).to.equal(0n);
      expect(await helper.lastAccount()).to.equal(ethers.ZeroHash);
    }
  });

  it("port shares the input cursor and budget across callbacks and finalizes output", async () => {
    const input = concat(encodeAmountBlock(asset, 3n), encodeAmountBlock(asset, 7n));
    expect(Array.from(await helper.executePort.staticCall(input, { value: 5n })))
      .to.deep.equal([concat(encodeAmountBlock(asset, 6n), encodeAmountBlock(asset, 14n)), 3n]);
    await (await helper.executePort(input, { value: 5n })).wait();
    expect(await helper.processed()).to.equal(2n);
    expect(await helper.lastAccount()).to.equal(ethers.ZeroHash);
    expect(await helper.lastCaller()).to.equal(await (await getSigner()).getAddress());
  });

  it("port returns the entire budget for empty input without invoking its callback", async () => {
    expect(Array.from(await helper.executePort.staticCall("0x", { value: 5n })))
      .to.deep.equal(["0x", 5n]);
    await (await helper.executePort("0x", { value: 5n })).wait();
    expect(await helper.processed()).to.equal(0n);
  });

  it("port rolls back prior callbacks on insufficient budget, malformed input, or hook failure", async () => {
    const first = encodeAmountBlock(asset, 3n);
    for (const [input, value, error] of [
      [concat(first, first), 1n, "InsufficientValue"],
      [concat(first, "0x01"), 5n, "OutOfBounds"],
      [concat(first, encodeAmountBlock(asset, 13n)), 5n, "RejectedRequest"],
    ] as const) {
      await expect(helper.executePort(input, { value, gasLimit: 1_000_000 }))
        .to.be.revertedWithCustomError(helper, error);
      expect(await helper.processed()).to.equal(0n);
      expect(await helper.lastCaller()).to.equal(ethers.ZeroAddress);
    }
  });
});
