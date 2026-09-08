import { expect } from "chai";
import { ethers } from "ethers";
import { commandId, deploy } from "./helpers/setup.js";
import { concat, encodeContextBlock, encodeRelayBlock, encodeStepBlock } from "./helpers/blocks.js";
import "./helpers/matchers.js";

describe("Command calls", () => {
  describe("invokeCommand", () => {
    const account = ethers.zeroPadValue("0xab", 32);
    const bytes = (length: number, byte = "a5") => "0x" + byte.repeat(length);
    let helper: Awaited<ReturnType<typeof deploy>>;

    before(async () => { helper = await deploy("TestDirtyCommandCalls"); });

    for (const handoff of [false, true]) {
      for (const stateLength of [0, 1, 7, 8, 9, 31, 32, 33, 63, 64, 65]) {
        it(`encodes canonical ${handoff ? "handoff" : "ordinary"} calls with ${stateLength} state bytes in dirty memory`, async () => {
          const command = await commandId("inspectCommand(bytes)", helper, handoff ? 0x81n : 0x01n);
          const state = bytes(stateLength);
          // Both the state/input boundary and the final ABI padding vary.
          for (const inputLength of [0, 1, 7, 8, 9, 31, 32, 33, 63, 64, 65]) {
            const input = bytes(inputLength, "b6");
            for (const remaining of handoff ? ["0x", encodeStepBlock(0n, 0n, bytes(inputLength, "c7"))] : ["0x"]) {
              const context = encodeContextBlock(account, state, handoff ? encodeRelayBlock(input, remaining) : input);
              const encoded = helper.interface.encodeFunctionData("inspectCommand", [context]);
              const steps = concat(encodeStepBlock(command, 7n, input), remaining);
              expect(await helper.testPipe.staticCall(account, state, steps, { value: 7n }))
                .to.equal(BigInt(ethers.keccak256(encoded)) ^ 7n);
            }
          }
        });
      }
    }

    it("preserves contexts and credits while returned state grows and shrinks across calls", async () => {
      const command = await commandId("replaceState(bytes)", helper, 0x01n);
      const outputs = [bytes(4097), bytes(1), bytes(65), bytes(31), bytes(8193), "0x"];
      const states = [bytes(33, "d8"), ...outputs.slice(0, -1)];
      const steps = concat(...outputs.map((input) => encodeStepBlock(command, 7n, input)));
      expect(await helper.testPipe.staticCall(account, states[0], steps, { value: 7n })).to.equal(7n);
      const tx = await helper.testPipe(account, states[0], steps, { value: 7n });
      const receipt = await tx.wait();
      const calls = receipt!.logs.map((log) => helper.interface.parseLog(log)).filter((log) => log?.name === "ContextCalled");
      expect(calls.map((log) => [...log!.args])).to.deep.equal(
        outputs.map((input, i) => [encodeContextBlock(account, states[i], input), 7n]),
      );
    });

    it("reuses large temporary inputs across repeated calls with empty outputs", async () => {
      const clean = await deploy("TestCommandCalls");
      const command = await commandId("discard(bytes)", clean);
      const steps = concat(...Array.from({ length: 8 }, () => encodeStepBlock(command, 0n, bytes(4096))));
      const [allocated, usedGas] = await clean.testPipeUsage.staticCall(account, "0x", steps);
      console.log(`        invokeCommand benchmark: ${allocated} bytes retained, ${usedGas} execution gas`);
      // Eight empty return tuples need far less retained memory than eight 4 KiB inputs.
      expect(allocated).to.be.lessThan(4096n);
    });
  });

  it("calls a selector with one memory bytes argument and forwards value", async () => {
    const helper = await deploy("TestCommandCalls");
    const selector = helper.interface.getFunction("echoBytes")!.selector;
    const input = "0xaabbcc";
    const value = 9n;

    const out = await helper.testRawCall.staticCall(
      selector,
      await helper.getAddress(),
      value,
      input,
      false,
      { value },
    );
    expect(out).to.equal(input);
  });

  it("returns decoded bytes when copying call input from calldata", async () => {
    const helper = await deploy("TestCommandCalls");
    const input = ethers.hexlify(ethers.randomBytes(33));
    const out = await helper.testRawCallCopy.staticCall(
      helper.interface.getFunction("echoBytes")!.selector,
      await helper.getAddress(),
      0n,
      input,
      false,
    );

    expect(out).to.equal(input);
  });

  it("optionally requires empty decoded call output", async () => {
    const helper = await deploy("TestCommandCalls");
    const selector = helper.interface.getFunction("echoBytes")!.selector;
    const target = await helper.getAddress();

    expect(await helper.testRawCall.staticCall(selector, target, 0n, "0x", true))
      .to.equal("0x");
    expect(await helper.testRawCallCopy.staticCall(selector, target, 0n, "0x", true))
      .to.equal("0x");
    for (const call of [
      () => helper.testRawCall.staticCall(selector, target, 0n, "0x01", true),
      () => helper.testRawCallCopy.staticCall(selector, target, 0n, "0x01", true),
    ]) {
      let data: string | undefined;
      try {
        await call();
      } catch (error: any) {
        data = error.data ?? error.info?.error?.data;
      }
      expect(data).to.equal("0x");
    }
  });

  it("handles bytes lengths around ABI word boundaries", async () => {
    const helper = await deploy("TestCommandCalls");
    const selector = helper.interface.getFunction("echoBytes")!.selector;
    const target = await helper.getAddress();

    for (const length of [0, 1, 31, 32, 33, 63, 64, 65]) {
      const input = ethers.hexlify(ethers.randomBytes(length));

      expect(await helper.testRawCall.staticCall(selector, target, 0n, input, false))
        .to.equal(input);
      expect(await helper.testRawCallCopy.staticCall(selector, target, 0n, input, false))
        .to.equal(input);
      expect(await helper.testTryRawCall.staticCall(selector, target, 0n, input))
        .to.equal(true);
      expect(await helper.testTryRawCallCopy.staticCall(selector, target, 0n, input))
        .to.equal(true);
    }
  });

  it("tries a selector call without reverting on target failure", async () => {
    const helper = await deploy("TestCommandCalls");
    const target = await helper.getAddress();
    const input = "0x010203";

    expect(await helper.testTryRawCall.staticCall(
      helper.interface.getFunction("echoBytes")!.selector,
      target,
      0n,
      input,
    )).to.equal(true);
    expect(await helper.testTryRawCall.staticCall(
      helper.interface.getFunction("failBytes")!.selector,
      target,
      0n,
      input,
    )).to.equal(false);
  });

  it("calls a single bytes argument directly from calldata", async () => {
    const helper = await deploy("TestCommandCalls");
    const selector = helper.interface.getFunction("echoBytes")!.selector;
    const target = await helper.getAddress();
    const input = ethers.hexlify(ethers.randomBytes(33));
    const value = 7n;

    const tx = await helper.testTryRawCallCopy(selector, target, value, input, { value });
    await expect(tx).to.emit(helper, "BytesCalled").withArgs(input, value);

    expect(await helper.testTryRawCallCopy.staticCall("0xffffffff", target, 0n, input))
      .to.equal(false);
  });

  for (const method of ["testTryRawCallGas", "testTryRawCallCopyGas"]) {
    it(`${method} limits call gas while preserving input and value forwarding`, async () => {
      const helper = await deploy("TestCommandCalls");
      const target = await helper.getAddress();
      const selector = helper.interface.getFunction("echoBytes")!.selector;
      const input = "0x" + "ab".repeat(33);
      expect(await helper[method].staticCall(selector, target, 0n, 0n, input))
        .to.equal(false);
      expect(await helper[method].staticCall(selector, target, 0n, 50_000n, input))
        .to.equal(true);
      const tx = await helper[method](selector, target, 7n, 50_000n, input, { value: 7n });
      await expect(tx).to.emit(helper, "BytesCalled").withArgs(input, 7n);
    });

    it(`${method} returns false when a capped callee runs out of gas`, async () => {
      const helper = await deploy("TestCommandCalls");
      const pipe = await deploy("TestOutOfGasPipe");
      const result = await helper[method].staticCall(
        pipe.interface.getFunction("portPipePayable")!.selector,
        await pipe.getAddress(), 0n, 30_000n, "0x", { gasLimit: 100_000n },
      );
      expect(result).to.equal(false);
    });
  }

  it("uses less gas when copying the bytes argument directly from calldata", async () => {
    const helper = await deploy("TestCommandCalls");
    const selector = helper.interface.getFunction("echoBytes")!.selector;
    const target = await helper.getAddress();
    const input = ethers.hexlify(ethers.randomBytes(97));

    const copied = await helper.testTryRawCallCopy.estimateGas(selector, target, 0n, input);
    const memory = await helper.testTryRawCall.estimateGas(selector, target, 0n, input);

    expect(copied).to.be.lessThan(memory);
  });

  it("queries bytes around ABI word boundaries", async () => {
    const helper = await deploy("TestCommandCalls");
    const selector = helper.interface.getFunction("queryBytes")!.selector;
    const target = await helper.getAddress();

    for (const length of [0, 1, 31, 32, 33, 63, 64, 65]) {
      const input = ethers.hexlify(ethers.randomBytes(length));
      expect(await helper.testRawQuery(selector, target, input))
        .to.equal(input);
    }
  });

  it("rejects queries with non-bytes return data", async () => {
    const helper = await deploy("TestCommandCalls");
    const selector = helper.interface.getFunction("noArgs")!.selector;

    let failure: string | undefined;
    try {
      await helper.testRawQuery(selector, await helper.getAddress(), "0x");
    } catch (error: any) {
      failure = error.data ?? error.info?.error?.data;
    }
    expect(failure).to.equal("0x");
  });

  it("preserves query failures in FailedCall", async () => {
    const helper = await deploy("TestCommandCalls");
    const target = await helper.getAddress();
    const selector = helper.interface.getFunction("failBytes")!.selector;
    const input = "0x010203";
    const reason = helper.interface.encodeErrorResult("TargetFailure", [3n]);
    const errors = new ethers.Interface([
      "error FailedCall(address addr, bytes4 selector, bytes err)",
    ]);

    let failureData: string | undefined;
    try {
      await helper.testRawQuery(selector, target, input);
    } catch (error: any) {
      failureData = error.data ?? error.info?.error?.data;
    }
    expect(errors.parseError(failureData!)?.args)
      .to.deep.equal([target, selector, reason]);
  });

  it("reports the separate selector when a raw call fails", async () => {
    const helper = await deploy("TestCommandCalls");
    const selector = helper.interface.getFunction("failBytes")!.selector;
    const target = await helper.getAddress();
    const input = "0x010203";
    const reason = helper.interface.encodeErrorResult("TargetFailure", [3n]);
    const errors = new ethers.Interface([
      "error FailedCall(address addr, bytes4 selector, bytes err)",
    ]);

    let data: string | undefined;
    try {
      await helper.testRawCall(selector, target, 0n, input, false);
    } catch (error: any) {
      data = error.data ?? error.info?.error?.data;
    }

    const failure = errors.parseError(data!);
    expect(failure?.name).to.equal("FailedCall");
    expect(failure?.args).to.deep.equal([target, selector, reason]);
  });

  it("rejects successful calls with invalid bytes return data", async () => {
    const helper = await deploy("TestCommandCalls");

    let data: string | undefined;
    try {
      await helper.testRawCall(
        helper.interface.getFunction("malformed")!.selector,
        await helper.getAddress(),
        0n,
        "0x",
        false,
      );
    } catch (error: any) {
      data = error.data ?? error.info?.error?.data;
    }

    expect(data).to.equal("0x");
  });

  it("calls command(bytes) with an exact context and decodes state and credit", async () => {
    const helper = await deploy("TestCommandCalls");
    const account = ethers.zeroPadValue("0xab", 32);
    const state = "0x0102030405";
    const input = "0xaabbccddeeff00";
    const value = 11n;
    const context = encodeContextBlock(account, state, input);
    const command = await commandId("command(bytes)", helper);
    const steps = encodeStepBlock(command, value, input);

    expect(
      await helper.testPipe.staticCall(
        account,
        state,
        steps,
        { value },
      ),
    ).to.equal(BigInt(ethers.keccak256(context)) ^ value);
  });

  it("wraps failed command calls in FailedCall", async () => {
    const helper = await deploy("TestCommandCalls");
    const selector = helper.interface.getFunction("failing")!.selector;
    const target = await helper.getAddress();
    const command = await commandId("failing(bytes)", helper);
    const steps = encodeStepBlock(command, 0n, "0x");
    const reason = helper.interface.encodeErrorResult("TargetFailure", [7n]);
    const errors = new ethers.Interface([
      "error FailedCall(address addr, bytes4 selector, bytes err)",
    ]);

    let data: string | undefined;
    try {
      await helper.testPipe(ethers.ZeroHash, "0x", steps);
    } catch (error: any) {
      data = error.data ?? error.info?.error?.data;
    }

    const failure = errors.parseError(data!);
    expect(failure?.name).to.equal("FailedCall");
    expect(failure?.args).to.deep.equal([
      await helper.getAddress(),
      selector,
      reason,
    ]);
  });

  it("rejects command return data with an invalid bytes offset", async () => {
    const helper = await deploy("TestCommandCalls");
    const command = await commandId("malformed(bytes)", helper);
    const steps = encodeStepBlock(command, 0n, "0x");

    let data: string | undefined;
    try {
      await helper.testPipe(ethers.ZeroHash, "0x", steps);
    } catch (error: any) {
      data = error.data ?? error.info?.error?.data;
    }

    expect(data).to.equal("0x");
  });

  for (const name of ["shortReturn", "oversizedLength", "trailingData"] as const) {
    it(`rejects ${name} command return data`, async () => {
      const helper = await deploy("TestCommandCalls");
      const command = await commandId(`${name}(bytes)`, helper);
      const steps = encodeStepBlock(command, 0n, "0x");

      let data: string | undefined;
      try {
        await helper.testPipe(ethers.ZeroHash, "0x", steps);
      } catch (error: any) {
        data = error.data ?? error.info?.error?.data;
      }

      expect(data).to.equal("0x");
    });
  }
});
