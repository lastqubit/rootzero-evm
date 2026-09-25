import { expect } from "chai";
import { ethers } from "ethers";
import { deploy } from "./helpers/setup.js";
import { concat, encodeStepBlock, Keys } from "./helpers/blocks.js";
import "./helpers/matchers.js";

describe("Pipeline parser and credit security", function () {
  this.timeout(120_000);
  let host: any;
  let local: bigint;
  let external: bigint;
  const panic = concat("0x4e487b71", ethers.toBeHex(0x11, 32));
  const selector = (name: string) => ethers.id(`${name}()`).slice(0, 10);
  async function failure(call: Promise<unknown>) {
    try { await call; } catch (e: any) { return e.data ?? e.error?.data ?? e.info?.error?.data; }
    throw new Error("Expected revert");
  }
  beforeEach(async () => {
    host = await deploy("TestPipelineOptimization");
    local = await host.localId();
    external = await host.externalId();
  });

  it("accepts maximum budget and emits the exact overflow panic with atomic rollback", async () => {
    for (const cmd of [local, external]) {
      const step = encodeStepBlock(cmd, 0n, ethers.toBeHex(1n, 32));
      expect((await host.measure.staticCall(step, ethers.MaxUint256 - 1n, "0x"))[1]).to.equal(ethers.MaxUint256);
      expect(await failure(host.measure(step, ethers.MaxUint256, "0x", { gasLimit: 1_000_000 }))).to.equal(panic);
      expect(await host.calls()).to.equal(0n);
      expect(await host.lastInput()).to.equal(ethers.ZeroHash);
    }
    const steps = concat(encodeStepBlock(local, 0n, ethers.toBeHex(ethers.MaxUint256, 32)),
      encodeStepBlock(local, 0n, ethers.toBeHex(1n, 32)));
    expect(await failure(host.measure(steps, 0n, "0x", { gasLimit: 1_000_000 }))).to.equal(panic);
    expect(await host.calls()).to.equal(0n);
  });

  it("preserves budget subtraction, refunds, authorization, and final state checks", async () => {
    expect((await host.measure.staticCall("0x", ethers.MaxUint256, "0x"))[1]).to.equal(ethers.MaxUint256);
    const step = encodeStepBlock(local, ethers.MaxUint256, ethers.toBeHex(ethers.MaxUint256, 32));
    expect((await host.measure.staticCall(step, ethers.MaxUint256, "0x"))[1]).to.equal(ethers.MaxUint256);
    expect(await failure(host.measure.staticCall(step, ethers.MaxUint256 - 1n, "0x"))).to.equal(selector("InsufficientValue"));
    expect(await failure(host.measure.staticCall("0x", 0n, "0x01"))).to.equal(selector("UnexpectedState"));
    for (const cmd of [local, external]) {
      await host.revoke(cmd);
      expect(await failure(host.measure.staticCall(encodeStepBlock(cmd, 0n, "0x"), 0n, "0x")))
        .to.equal(selector("AccessDenied"));
    }
  });

  it("threads exact input slices through internal and external commands and preserves events", async () => {
    const inputs = ["0x", "0x123456", concat(ethers.ZeroHash, "0xabcd")];
    const steps = concat(...inputs.map((input, i) => encodeStepBlock(i % 2 ? external : local, 0n, input)));
    expect((await host.measure.staticCall(steps, 42n, "0x"))[1]).to.equal(42n);
    const receipt = await (await host.measure(steps, 42n, "0x")).wait();
    const events = receipt.logs.map((log: any) => host.interface.parseLog(log));
    expect(events.map((event: any) => [event.args.input, event.args.assigned]))
      .to.deep.equal(inputs.map(input => [input, 0n]));
    expect(await host.calls()).to.equal(3n);
    expect(await host.lastInput()).to.equal(ethers.keccak256(inputs[2]));
  });

  it("preserves STEP/BYTES/length/containment error precedence and rolls back preceding steps", async () => {
    const valid = encodeStepBlock(local, 0n, "0x");
    const replace = (s: string, at: number, value: string) => concat(ethers.dataSlice(s, 0, at), value,
      ethers.dataSlice(s, at + ethers.dataLength(value)));
    const badKey = replace(valid, 0, "0xffffffff");
    const badChild = replace(valid, 72, "0xffffffff");
    const wrongEnd = replace(valid, 4, ethers.toBeHex(73, 4));
    const outside = replace(wrongEnd, 76, ethers.toBeHex(1, 4));
    for (const [bad, error] of [[badKey, "InvalidBlock"], [badChild, "InvalidBlock"],
      [wrongEnd, "InvalidBlock"], [outside, "OutOfBounds"], [concat(valid, "0x01"), "InvalidBlock"]]) {
      expect(await failure(host.measure(concat(valid, bad), 0n, "0x", { gasLimit: 1_000_000 })))
        .to.equal(selector(error));
      expect(await host.calls()).to.equal(0n);
    }
  });

  it("fuzzes parser keys, lengths, truncation, and containment against a bounded reference model", async () => {
    let seed = 0x139039;
    const random = () => { seed ^= seed << 13; seed ^= seed >>> 17; seed ^= seed << 5; return seed >>> 0; };
    const read32 = (data: Uint8Array, at: number) => {
      let value = 0; for (let i = 0; i < 4; i++) value = value * 256 + (data[at + i] ?? 0); return value;
    };
    const model = (data: Uint8Array) => {
      let at = 0;
      while (at < data.length) {
        if (read32(data, at) !== Number(BigInt(Keys.Step))) return "InvalidBlock";
        const end = at + 8 + read32(data, at + 4);
        if (read32(data, at + 72) !== Number(BigInt(Keys.Bytes))) return "InvalidBlock";
        if (at + 80 + read32(data, at + 76) !== end) return "InvalidBlock";
        if (end > data.length) return "OutOfBounds";
        at = end;
      }
      return null;
    };
    for (let trial = 0; trial < 256; trial++) {
      const payload = "0x" + "00".repeat(random() % 65);
      let data = ethers.getBytes(encodeStepBlock(trial % 2 ? local : external, 0n, payload));
      const mode = trial % 6;
      if (mode < 4) {
        const offset = [0, 4, 72, 76][mode];
        data.set(ethers.getBytes(ethers.toBeHex(random(), 4)), offset);
      } else if (mode === 4) data = data.slice(0, random() % data.length);
      const expected = model(data);
      if (expected) expect(await failure(host.measure.staticCall(data, 0n, "0x")), `trial ${trial}`)
        .to.equal(selector(expected));
      else expect((await host.measure.staticCall(data, 0n, "0x"))[1]).to.equal(0n);
    }
  });

  it("fuzzes returned-credit arithmetic against full-width bigint accounting", async () => {
    for (let trial = 0; trial < 128; trial++) {
      const budget = BigInt(ethers.keccak256(ethers.toUtf8Bytes(`budget:${trial}`)));
      const value = BigInt(ethers.keccak256(ethers.toUtf8Bytes(`assigned:${trial}`))) % (budget + 1n);
      const credit = BigInt(ethers.keccak256(ethers.toUtf8Bytes(`credit:${trial}`)));
      const expected = budget - value + credit;
      const steps = encodeStepBlock(local, value, ethers.toBeHex(credit, 32));
      if (expected > ethers.MaxUint256) expect(await failure(host.measure.staticCall(steps, budget, "0x"))).to.equal(panic);
      else expect((await host.measure.staticCall(steps, budget, "0x"))[1]).to.equal(expected);
    }
  });
});
