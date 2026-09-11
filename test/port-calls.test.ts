import { expect } from "chai";
import { ethers } from "ethers";
import { deploy, getProvider } from "./helpers/setup.js";
import "./helpers/matchers.js";

describe("Port call helpers", () => {
  let helper: Awaited<ReturnType<typeof deploy>>;
  let target: Awaited<ReturnType<typeof deploy>>;
  const abi = ethers.AbiCoder.defaultAbiCoder();
  const word = (value: bigint) => ethers.toBeHex(value, 32);

  before(async () => {
    helper = await deploy("TestCommandCalls");
    target = await deploy("TestCommandCalls");
  });

  async function revertData(call: Promise<unknown>) {
    let data: string | undefined;
    try { await call; } catch (error: any) {
      data = error.data ?? error.info?.error?.data;
    }
    return data;
  }

  for (const method of ["testRawCall", "testRawCallCopy"]) {
    describe(method, () => {
      it("decodes output around ABI word boundaries and independent trusted credit", async () => {
        for (const length of [0, 1, 31, 32, 33, 63, 64, 65, 4097]) {
          const output = "0x" + "a5".repeat(length);
          for (const credit of [0n, 123n, ethers.MaxUint256]) {
            const encoded = abi.encode(["bytes", "uint256"], [output, credit]);
            expect(await helper[method].staticCall(
              target.interface.getFunction("returnRaw")!.selector,
              await target.getAddress(), 0n, encoded, false,
            )).to.deep.equal([output, credit]);
          }
        }
      });

      it("forwards the input and ETH without treating returned credit as an ETH refund", async () => {
        const address = await target.getAddress();
        const selector = target.interface.getFunction("echoPort")!.selector;
        const input = "0x" + "bc".repeat(33);
        expect(await helper[method].staticCall(selector, address, 7n, input, false, { value: 7n }))
          .to.deep.equal([input, 7n]);
        const provider = await getProvider();
        const tx = await helper[method](selector, address, 7n, input, false, { value: 7n });
        await expect(tx).to.emit(target, "BytesCalled").withArgs(input, 7n);
        const receipt = await tx.wait();
        const before = await provider.getBalance(address, receipt!.blockNumber - 1);
        const after = await provider.getBalance(address, receipt!.blockNumber);
        expect(after - before).to.equal(7n);
      });

      it("requires empty output when requested while allowing nonzero credit", async () => {
        const selector = target.interface.getFunction("echoPort")!.selector;
        const address = await target.getAddress();
        expect(await helper[method].staticCall(selector, address, 5n, "0x", true, { value: 5n }))
          .to.deep.equal(["0x", 5n]);
        expect(await revertData(helper[method].staticCall(selector, address, 0n, "0x01", true)))
          .to.equal("0x");
      });

      const malformed: Record<string, string> = {
        empty: "0x",
        "short head": ethers.concat([word(64n), word(0n)]),
        "legacy bytes result": abi.encode(["bytes"], ["0x1234"]),
        "wrong offset": ethers.concat([word(32n), word(0n), word(0n)]),
        "oversized length": ethers.concat([word(64n), word(0n), word(32n)]),
        "overflowing length": ethers.concat([word(64n), word(0n), word(ethers.MaxUint256)]),
        "missing padding": ethers.concat([word(64n), word(0n), word(1n), "0xaa"]),
        "trailing word": ethers.concat([abi.encode(["bytes", "uint256"], ["0x", 0n]), word(0n)]),
        "trailing byte": ethers.concat([abi.encode(["bytes", "uint256"], ["0xab", 0n]), "0x00"]),
      };
      for (const [name, data] of Object.entries(malformed)) {
        it(`rejects ${name}`, async () => {
          expect(await revertData(helper[method].staticCall(
            target.interface.getFunction("returnRaw")!.selector,
            await target.getAddress(), 0n, data, false,
          ))).to.equal("0x");
        });
      }

      it("preserves target, selector, and revert data in FailedCall", async () => {
        const selector = target.interface.getFunction("failBytes")!.selector;
        const address = await target.getAddress();
        const errors = new ethers.Interface(["error FailedCall(address addr, bytes4 selector, bytes err)"]);
        const data = await revertData(helper[method].staticCall(selector, address, 0n, "0x010203", false));
        expect(errors.parseError(data!)?.args).to.deep.equal([
          address, selector, target.interface.encodeErrorResult("TargetFailure", [3n]),
        ]);
      });

      it("rejects a successful call to an address without code", async () => {
        expect(await revertData(helper[method].staticCall("0x12345678", ethers.ZeroAddress, 0n, "0x", false)))
          .to.equal("0x");
      });
    });
  }
});
