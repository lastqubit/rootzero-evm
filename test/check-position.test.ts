import { expect } from "chai";
import { ethers } from "ethers";
import { deploy, getSigner, commandId } from "./helpers/setup.js";
import { concat, encodePositionBlock, encodePositionLimitsBlock, encodeQuoteBlock, encodeContextBlock, endpointDescriptor, Keys } from "./helpers/blocks.js";
import "./helpers/matchers.js";

describe("CheckPosition command", () => {
  const asset = ethers.toBeHex(1n, 32);
  const liability = ethers.toBeHex(2n, 32);
  const counterparty = ethers.toBeHex(3n, 32);
  const position = (amount = 100n, debt = 40n) => encodePositionBlock(asset, amount, liability, debt, counterparty);
  const limits = (amount = 100n, debt = 40n) => encodePositionLimitsBlock(asset, amount, liability, debt);
  let host: any;
  before(async () => { host = await deploy("TestCheckPosition"); });

  it("accepts the canonical Solidity schema headers in memory execution", async () => {
    const [positionHeader, limitsHeader] = await host.schemaHeaders();
    const state = ethers.toBeHex(positionHeader, 8) + position().slice(18);
    const input = ethers.toBeHex(limitsHeader, 8) + limits().slice(18);
    expect((await host.checkMemory(state, input, 0n))[1]).to.equal(state);
  });

  it("registers the POSITION / POSITION_LIMITS / POSITION command", async () => {
    const id = await commandId("checkPosition(bytes)", host);
    expect(await host.commandId()).to.equal(id);
    await expect(host.deploymentTransaction()).to.emit(host, "Endpoint").withArgs(await host.host(), id,
      endpointDescriptor({ state: Keys.Position, stateHint: 160, input: Keys.PositionLimits,
        output: BigInt(Keys.Position) << 224n | 160n << 136n }));
  });

  for (const memory of [false, true]) describe(memory ? "Execute" : "normal", () => {
    const run = async (state: string, input: string) => {
      if (memory) {
        const result = await host.checkMemory(state, input, 123n);
        expect(result[0]).to.equal(true);
        expect(result[2]).to.equal(123n);
        return result[1];
      }
      const result = await host.checkPosition.staticCall(encodeContextBlock(counterparty, state, input));
      expect(result[1]).to.equal(0n);
      return result[0];
    };

    it("rejects QUOTE input even though its payload has the same layout", async () => {
      await expect(run(position(), encodeQuoteBlock(asset, 100n, liability, 40n)))
        .to.be.revertedWithCustomError(host, "InvalidBlock");
    });

    it("preserves empty state and complete batches including counterparties", async () => {
      expect(await run("0x", "0x")).to.equal("0x");
      const state = concat(position(), position(ethers.MaxUint256, ethers.MaxUint256), position(0n, 0n));
      expect(await run(state, concat(limits(), limits(ethers.MaxUint256, ethers.MaxUint256), limits(0n, 0n))))
        .to.equal(state);
      expect(await run(position(), limits(99n, 41n))).to.equal(position());
    });

    it("rejects either identifier mismatch before quantity errors", async () => {
      for (const input of [encodePositionLimitsBlock(liability, 101n, liability, 39n), encodePositionLimitsBlock(asset, 101n, asset, 39n)]) {
        await expect(run(position(), input)).to.be.revertedWithCustomError(host, "UnexpectedValue");
      }
    });

    it("enforces both inclusive full-width bounds including later batch entries", async () => {
      for (const input of [limits(101n, 40n), limits(100n, 39n), limits(0n, 0n)]) {
        await expect(run(concat(position(), position()), concat(limits(), input)))
          .to.be.revertedWithCustomError(host, "OutOfRange");
      }
      await expect(run(position(ethers.MaxUint256, ethers.MaxUint256), limits(0n, ethers.MaxUint256 - 1n)))
        .to.be.revertedWithCustomError(host, "OutOfRange");
    });

    it("rejects missing, extra, truncated, and mismatched block streams", async () => {
      for (const [state, input] of [
        [position(), "0x"], ["0x", limits()], [position(), concat(limits(), limits())],
        [position().slice(0, -2), limits()], [position(), limits().slice(0, -2)],
        [concat(position(), position()), limits()],
      ]) await expect(run(state, input)).to.be.revertedWithCustomError(host, memory ? "InvalidBlock" : "OutOfBounds");
    });

    it("validates exact keys and sizes for both block headers", async () => {
      const badKey = (block: string) => "0xffffffff" + block.slice(10);
      const badSize = (block: string) => block.slice(0, 10) + "00000000" + block.slice(18);
      for (const corrupt of [badKey, badSize]) {
        await expect(run(corrupt(position()), limits())).to.be.revertedWithCustomError(host, "InvalidBlock");
        await expect(run(position(), corrupt(limits()))).to.be.revertedWithCustomError(host, "InvalidBlock");
      }
    });
  });

  it("enforces normal command access and rejects trailing context data", async () => {
    const context = encodeContextBlock(counterparty, position(), limits());
    await expect(host.connect(await getSigner(1)).checkPosition(context)).to.be.revertedWithCustomError(host, "AccessDenied");
    await expect(host.checkPosition(concat(context, "0x00"))).to.be.revertedWithCustomError(host, "InvalidBlock");
  });
});
