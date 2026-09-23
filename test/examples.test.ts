import { expect } from "chai";
import { ethers } from "ethers";
import { deploy, getSigner, hostId } from "./helpers/setup.js";
import "./helpers/matchers.js";
import {
  Keys,
  concat,
  encodeAssetBlock,
  encodeAmountBlock,
  encodeBalanceBlock,
  encodeBlock,
  encodeStatusBlock,
  encodeNodeBlock,
  encodeCustodyBlock,
  encodeContextBlock,
  encodeBytesBlock,
  encodeListBlock,
  encodeTxBlock,
  encodeUserAccount,
  localKey,
  pad32,
} from "./helpers/blocks.js";

const Payment = localKey(1);
const Swap = localKey(1);
const SwapHop = localKey(2);

function uint32(value: bigint): string {
  return ethers.toBeHex(value, 4);
}

function int32(value: bigint): string {
  return ethers.toBeHex(ethers.toTwos(value, 32), 4);
}

describe("Examples", () => {
  describe("Commands barrel", () => {
    it("builds and runs the single-input command example", async () => {
      const signer = await getSigner(0);
      const commander = await signer.getAddress();
      const host = await deploy("TestBasicCommandExampleHost", await hostId(commander));
      const account = encodeUserAccount(commander);
      const asset = ethers.zeroPadValue("0x01", 32);

      const [output, transactions] = await host.myCommand.staticCall(
        encodeContextBlock(account, "0x", encodeAmountBlock(asset, 12n)),
      );

      expect(output).to.equal(encodeBalanceBlock(asset, 12n));
      expect(transactions).to.equal(0n);
      await expect(host.myCommand.staticCall(encodeContextBlock(account, "0x", "0x")))
        .to.be.revertedWithCustomError(host, "OutOfBounds");
      const amount = encodeAmountBlock(asset, 12n);
      await expect(host.myCommand.staticCall(encodeContextBlock(account, "0x", concat(amount, amount))))
        .to.be.revertedWithCustomError(host, "UnconsumedData");
    });

    it("builds and runs the batch command example", async () => {
      const signer = await getSigner(0);
      const commander = await signer.getAddress();
      const host = await deploy("TestBatchCommandExampleHost", await hostId(commander));
      const account = encodeUserAccount(commander);
      const first = ethers.zeroPadValue("0x11", 32);
      const second = ethers.zeroPadValue("0x22", 32);

      const [output, transactions] = await host.myCommand.staticCall(
        encodeContextBlock(
          account,
          "0x",
          concat(encodeAmountBlock(first, 10n), encodeAmountBlock(second, 20n)),
        ),
      );

      expect(output).to.equal(concat(
        encodeBalanceBlock(first, 10n),
        encodeBalanceBlock(second, 20n),
      ));
      expect(transactions).to.equal(0n);
    });

    it("builds and runs the custom-data command example", async () => {
      const signer = await getSigner(0);
      const commander = await signer.getAddress();
      const host = await deploy("TestDataCommandExampleHost", await hostId(commander));
      const account = encodeUserAccount(commander);
      const asset = ethers.zeroPadValue("0x33", 32);
      const target = 77n;
      const input = encodeBlock(Payment, concat(pad32(target), encodeAmountBlock(asset, 30n)));

      const context = encodeContextBlock(account, "0x", input);
      const [output, transactions] = await host.myCommand.staticCall(context);
      expect(output).to.equal(encodeCustodyBlock(target, asset, 30n));
      expect(transactions).to.equal(0n);
      await expect(host.myCommand(context))
        .to.emit(host, "SentToHost")
        .withArgs(target, asset, 30n);
    });

    it("builds and runs the custom-keyed top-level list example", async () => {
      const signer = await getSigner(0);
      const commander = await signer.getAddress();
      const host = await deploy("TestListCommandExampleHost", await hostId(commander));
      const account = encodeUserAccount(commander);
      const first = ethers.zeroPadValue("0x44", 32);
      const second = ethers.zeroPadValue("0x55", 32);
      const listKey = localKey(1);
      const input = concat(
        encodeBlock(listKey, concat(encodeAssetBlock(first), encodeAssetBlock(second))),
        encodeBlock(listKey, encodeAssetBlock(first)),
      );

      const tx = host.myCommand(encodeContextBlock(account, "0x", input));
      await expect(tx).to.emit(host, "AssetSeen").withArgs(0n, first);
      await expect(tx).to.emit(host, "AssetSeen").withArgs(0n, second);
      await expect(tx).to.emit(host, "AssetSeen").withArgs(1n, first);
    });

  });

  describe("7-CustomInput", () => {
    it("decodes populated and empty child blocks with the custom unpack helper", async () => {
      const signer = await getSigner(0);
      const commander = await signer.getAddress();
      const host = await deploy("TestFrameExampleHost", await hostId(commander));

      const account = encodeUserAccount(commander);
      const asset = ethers.zeroPadValue("0x01", 32);
      const amount = 123n;
      const status = 4n;
      const input = encodeBlock(Payment, concat(asset, pad32(amount), encodeStatusBlock(status)));

      await expect(host.myCommand(encodeContextBlock(account, "0x", input)))
        .to.emit(host, "PaymentSeen")
        .withArgs(asset, amount, status);

      const emptyStatus = encodeBlock(Payment, concat(asset, pad32(amount), encodeBlock(Keys.Status, "0x")));
      await expect(host.myCommand(encodeContextBlock(account, "0x", emptyStatus)))
        .to.emit(host, "PaymentSeen")
        .withArgs(asset, amount, 0n);

      const missingStatus = encodeBlock(Payment, concat(asset, pad32(amount)));
      await expect(host.myCommand(encodeContextBlock(account, "0x", missingStatus)))
        .to.be.revertedWithCustomError(host, "InvalidBlock");
    });
  });

  describe("8-BudgetCredit", () => {
    it("returns a trusted budget credit derived from every input batch", async () => {
      const signer = await getSigner(0);
      const commander = await signer.getAddress();
      const host = await deploy("TestTransactionsExampleHost", await hostId(commander));

      const account = encodeUserAccount(commander);
      const input = concat(
        encodeNodeBlock(10n),
        encodeNodeBlock(20n),
      );

      const [output, credit] = await host.myCommand.staticCall(
        encodeContextBlock(account, "0x", input),
      );

      expect(output).to.equal("0x");
      expect(credit).to.equal(30n);
    });
  });

  describe("9-Swap", () => {
    it("decodes swap configuration and its nested hop list", async () => {
      const signer = await getSigner(0);
      const commander = await signer.getAddress();
      const host = await deploy("TestSwapExampleHost", await hostId(commander));
      const account = encodeUserAccount(commander);

      const asset = ethers.zeroPadValue("0x10", 32);
      const liability = ethers.zeroPadValue("0x20", 32);
      const firstHopAsset = ethers.zeroPadValue("0x30", 32);
      const secondHopAsset = ethers.zeroPadValue("0x40", 32);
      const hookData = "0xaabb";
      const firstHopData = "0xcc";

      const firstHop = encodeBlock(SwapHop, concat(
        firstHopAsset,
        uint32(500n),
        int32(-10n),
        pad32(11n),
        encodeBytesBlock(firstHopData),
      ));
      const secondHop = encodeBlock(SwapHop, concat(
        secondHopAsset,
        uint32(3000n),
        int32(60n),
        pad32(12n),
        encodeBytesBlock("0x"),
      ));
      const input = encodeBlock(Swap, concat(
        uint32(100n),
        int32(-5n),
        pad32(9n),
        encodeBytesBlock(hookData),
        asset,
        pad32(100n),
        liability,
        pad32(25n),
        encodeListBlock(firstHop, secondHop),
      ));

      const [output, transactions] = await host.swap.staticCall(
        encodeContextBlock(account, "0x", input),
      );
      expect(output).to.equal("0x");
      expect(transactions).to.equal(0n);
    });
  });
});
