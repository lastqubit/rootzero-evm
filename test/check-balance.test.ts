import { expect } from "chai";
import { ethers } from "ethers";
import { deploy, getSigner, commandId } from "./helpers/setup.js";
import { concat, encodeBalanceBlock, encodeAssetLimitsBlock, encodePositionBlock, encodePositionLimitsBlock, encodeLimitsBlock, encodeContextBlock, endpointDescriptor, Keys, MaxUint128 } from "./helpers/blocks.js";
import "./helpers/matchers.js";

describe("CheckBalance command", () => {
  const asset = ethers.toBeHex(1n, 32);
  const account = ethers.toBeHex(3n, 32);
  const balance = (amount = 100n) => encodeBalanceBlock(asset, amount);
  const limits = (minimum = 90n, maximum = 110n) => encodeAssetLimitsBlock(asset, minimum, maximum);
  let host: any;
  before(async () => { host = await deploy("TestCheckBalance"); });

  it("composes both check commands in one host", async () => {
    const liability = ethers.toBeHex(2n, 32);
    const position = encodePositionBlock(asset, 100n, liability, 40n);
    expect(await host.checkBalance.staticCall(encodeContextBlock(account, balance(), limits())))
      .to.deep.equal([balance(), 0n]);
    expect(await host.checkPosition.staticCall(encodeContextBlock(account, position,
      encodePositionLimitsBlock(asset, 100n, liability, 40n))))
      .to.deep.equal([position, 0n]);
  });

  it("accepts the canonical Solidity schema headers in memory execution", async () => {
    const [balanceHeader, limitsHeader] = await host.schemaHeaders();
    const state = ethers.toBeHex(balanceHeader, 8) + balance().slice(18);
    const input = ethers.toBeHex(limitsHeader, 8) + limits().slice(18);
    expect((await host.checkMemory(state, input, 0n))[1]).to.equal(state);
  });

  it("registers the BALANCE / ASSET_LIMITS / BALANCE command", async () => {
    const id = await commandId("checkBalance(bytes)", host);
    expect(await host.commandId()).to.equal(id);
    await expect(host.deploymentTransaction()).to.emit(host, "Endpoint").withArgs(await host.host(), id,
      endpointDescriptor({ state: Keys.Balance, stateHint: 64, input: Keys.AssetLimits,
        output: BigInt(Keys.Balance) << 224n | 64n << 136n }));
  });

  for (const memory of [false, true]) describe(memory ? "Execute" : "normal", () => {
    const run = async (state: string, input: string) => {
      if (memory) {
        const result = await host.checkMemory(state, input, 123n);
        expect(result[0]).to.equal(true);
        expect(result[2]).to.equal(123n);
        return result[1];
      }
      const result = await host.checkBalance.staticCall(encodeContextBlock(account, state, input));
      expect(result[1]).to.equal(0n);
      return result[0];
    };

    it("preserves empty state, batch quantities, and distinct asset identifiers", async () => {
      expect(await run("0x", "0x")).to.equal("0x");
      const state = concat(balance(), encodeBalanceBlock(ethers.toBeHex(ethers.MaxUint256, 32), 0n), balance(MaxUint128));
      expect(await run(state, concat(limits(), encodeAssetLimitsBlock(ethers.toBeHex(ethers.MaxUint256, 32), 0n, 0n), limits(MaxUint128, MaxUint128)))).to.equal(state);
    });

    it("accepts inclusive lower and upper bounds and interior amounts", async () => {
      for (const amount of [90n, 100n, 110n]) expect(await run(balance(amount), limits())).to.equal(balance(amount));
      expect(await run(balance(100n), limits(100n, 100n))).to.equal(balance(100n));
      for (const amount of [MaxUint128 + 1n, 1n << 255n, ethers.MaxUint256]) {
        expect(await run(balance(amount), limits(amount, amount))).to.equal(balance(amount));
        expect(await run(balance(amount), limits(0n, ethers.MaxUint256))).to.equal(balance(amount));
      }
    });

    it("rejects the wrong asset before quantity bounds, including zero balances", async () => {
      for (const amount of [0n, 100n]) {
        await expect(run(balance(amount), encodeAssetLimitsBlock(account, 101n, 99n)))
          .to.be.revertedWithCustomError(host, "UnexpectedValue");
      }
      await expect(run(concat(balance(), balance()), concat(limits(), encodeAssetLimitsBlock(account, 0n, ethers.MaxUint256))))
        .to.be.revertedWithCustomError(host, "UnexpectedValue");
    });

    it("rejects the former packed LIMITS input", async () => {
      await expect(run(balance(), encodeLimitsBlock(90n, 110n)))
        .to.be.revertedWithCustomError(host, memory ? "InvalidBlock" : "OutOfBounds");
    });

    it("rejects either violated bound, inverted ranges, and full-width values without truncation", async () => {
      for (const [amount, minimum, maximum] of [
        [89n, 90n, 110n], [111n, 90n, 110n], [100n, 110n, 90n],
        [0n, 1n, 0n], [1n, 1n, 0n], [1n, 0n, 0n],
        [MaxUint128 + 1n, 0n, MaxUint128], [1n << 255n, 0n, MaxUint128], [ethers.MaxUint256, 0n, MaxUint128],
        [ethers.MaxUint256, 0n, ethers.MaxUint256 - 1n], [ethers.MaxUint256 - 1n, ethers.MaxUint256, ethers.MaxUint256],
      ]) await expect(run(balance(amount), limits(minimum, maximum))).to.be.revertedWithCustomError(host, "OutOfRange");
      await expect(run(concat(balance(), balance(111n)), concat(limits(), limits())))
        .to.be.revertedWithCustomError(host, "OutOfRange");
    });

    it("rejects missing, extra, truncated, and mismatched block streams", async () => {
      for (const [state, input] of [
        [balance(), "0x"], ["0x", limits()], [balance(), concat(limits(), limits())],
        [balance().slice(0, -2), limits()], [balance(), limits().slice(0, -2)],
        [concat(balance(), balance()), limits()],
      ]) await expect(run(state, input)).to.be.revertedWithCustomError(host, memory ? "InvalidBlock" : "OutOfBounds");
    });

    it("validates exact keys and sizes before checking amounts", async () => {
      const badKey = (block: string) => "0xffffffff" + block.slice(10);
      const badSize = (block: string) => block.slice(0, 10) + "00000000" + block.slice(18);
      for (const corrupt of [badKey, badSize]) {
        await expect(run(corrupt(balance(0n)), limits())).to.be.revertedWithCustomError(host, "InvalidBlock");
        await expect(run(balance(0n), corrupt(limits()))).to.be.revertedWithCustomError(host, "InvalidBlock");
      }
    });
  });

  it("enforces normal command access and rejects trailing context data", async () => {
    const context = encodeContextBlock(account, balance(), limits());
    await expect(host.connect(await getSigner(1)).checkBalance(context)).to.be.revertedWithCustomError(host, "AccessDenied");
    await expect(host.checkBalance(concat(context, "0x00"))).to.be.revertedWithCustomError(host, "InvalidBlock");
  });
});
