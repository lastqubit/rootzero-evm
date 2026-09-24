import { expect } from "chai";
import { ethers } from "ethers";
import { deploy } from "./helpers/setup.js";
import "./helpers/matchers.js";
import {
  Keys,
  encodeActionBlock,
  encodeCounterpartyBlock,
  encodeAccountAmountBlock,
  encodeAllocationBlock,
  encodeAllowanceBlock,
  encodeAmountBlock,
  encodeAssetBlock,
  encodeAssetLiabilityBlock,
  encodeBalanceBlock,
  encodeBootstrapBlock,
  encodeLiabilityPosition,
  encodePositionBlock,
  encodeBytesBlock,
  encodeCallBlock,
  encodeRelayBlock,
  encodeDispatchBlock,
  encodeListBlock,
  encodeCustodyBlock,
  encodeAccountBlock,
  encodeAccountAssetBlock,
  encodeContextBlock,
  encodeRecoverBlock,
  encodeHostAccountAssetBlock,
  encodeHostAssetBlock,
  encodeBlock,
  encodeLabelBlock,
  encodeNodeBlock,
  encodeSchemaBlock,
  encodeStatusBlock,
  encodeStringBlock,
  encodeStepBlock,
  encodeTxBlock,
  encodeUserAccount,
  exactSpec,
  concat,
  localKey,
  pad32,
  rangedSpec,
} from "./helpers/blocks.js";

describe("Cursors", () => {
  let helper: Awaited<ReturnType<typeof deploy>>;
  let blocksHelper: Awaited<ReturnType<typeof deploy>>;
  let stringHelper: Awaited<ReturnType<typeof deploy>>;
  let erc20Helper: Awaited<ReturnType<typeof deploy>>;
  let operation: Awaited<ReturnType<typeof deploy>>;
  let utils: Awaited<ReturnType<typeof deploy>>;

  before(async () => {
    helper = await deploy("TestCursorHelper");
    blocksHelper = await deploy("TestBlocksHelper");
    stringHelper = await deploy("TestStringCursorHelper");
    erc20Helper = await deploy("TestErc20CursorHelper");
    operation = await deploy("TestOperation");
    utils = await deploy("TestUtils");
  });

  describe("Writers", () => {
    const asset = ethers.zeroPadValue("0x01", 32);
    const amount = 12345n;

    it("reads raw words from absolute calldata positions", async () => {
      const prefix = "0xaabbcc";
      const word = pad32(amount);
      const source = concat(prefix, word);

      expect(await blocksHelper.read32(source, 3)).to.equal(word);
      expect(await blocksHelper.read32AsUint(source, 3)).to.equal(amount);
    });

    it("reads equal words at distinct unaligned or identical positions", async () => {
      const word = ethers.hexlify(Uint8Array.from({ length: 32 }, (_, i) => i + 1));
      const source = concat("0xaabbcc", word, word);
      expect(await blocksHelper.readEqualAt32(source, 3, 35)).to.equal(word);
      expect(await blocksHelper.readEqualAt32(source, 35, 3)).to.equal(word);
      expect(await blocksHelper.readEqualAt32(source, 3, 3)).to.equal(word);
    });

    it("reverts with UnexpectedValue when any byte differs", async () => {
      const word = new Uint8Array(32).fill(0xab);
      for (let i = 0; i < 32; ++i) {
        const other = word.slice();
        other[i] ^= 1;
        await expect(blocksHelper.readEqualAt32(concat(ethers.hexlify(word), ethers.hexlify(other)), 0, 32))
          .to.be.revertedWithCustomError(blocksHelper, "UnexpectedValue");
      }
    });

    it("preserves unchecked zero-padding for equal-word reads", async () => {
      const word = "0xab" + "00".repeat(31);
      expect(await blocksHelper.readEqualAt32(concat(word, "0xab"), 0, 32)).to.equal(word);
      expect(await blocksHelper.readEqualAt32("0x", 1024, 2048)).to.equal(ethers.ZeroHash);
      await expect(blocksHelper.readEqualAt32(word, 0, 1024))
        .to.be.revertedWithCustomError(blocksHelper, "UnexpectedValue");
    });

    describe("Comparison reads", () => {
      const comparisons: [string, (a: bigint, b: bigint) => boolean][] = [
        ["readEqualAt32", (a, b) => a === b],
        ["readNotEqualAt32", (a, b) => a !== b],
        ["readLtAt32", (a, b) => a < b],
        ["readLeAt32", (a, b) => a <= b],
        ["readGtAt32", (a, b) => a > b],
        ["readGeAt32", (a, b) => a >= b],
      ];

      for (const [name, compare] of comparisons) {
        const error = name === "readEqualAt32" || name === "readNotEqualAt32"
          ? "UnexpectedValue" : "OutOfRange";
        async function check(source: string, i: number, j: number, a: bigint, b: bigint) {
          const result = blocksHelper[name](source, i, j);
          if (compare(a, b)) {
            if (name === "readEqualAt32") expect(await result).to.equal(pad32(a));
            else expect([...(await result)]).to.deep.equal([pad32(a), pad32(b)]);
          }
          else {
            // Assembly-only reverts are not necessarily included in the compiler's ABI.
            await result.then(
              () => expect.fail(`Expected ${error}()`),
              (revert: { data: string }) => expect(revert.data).to.equal(ethers.id(`${error}()`).slice(0, 10)),
            );
          }
        }

        it(`${name} compares unsigned words and returns values in argument order at unaligned positions`, async () => {
          const values = [0n, 1n, (1n << 255n) - 1n, 1n << 255n, ethers.MaxUint256];
          for (const a of values) {
            for (const b of values) {
              await check(concat("0xaabbcc", pad32(a), pad32(b)), 3, 35, a, b);
              await check(concat("0xaabbcc", pad32(a), pad32(b)), 35, 3, b, a);
            }
          }
        });

        it(`${name} handles identical positions and unchecked zero-padding`, async () => {
          await check(pad32(7n), 0, 0, 7n, 7n);
          await check("0x", 1024, 2048, 0n, 0n);
          await check(pad32(1n), 0, 1024, 1n, 0n);
          await check(pad32(1n), 1024, 0, 0n, 1n);
          const partial = 0xabn << 248n;
          await check(concat(pad32(partial), "0xab"), 0, 32, partial, partial);
        });
      }
    });

    it("reads every power-of-two byte width from absolute calldata positions", async () => {
      const prefix = "0xaabbcc";
      const word = ethers.hexlify(Uint8Array.from({ length: 32 }, (_, i) => i + 1));
      const [one, two, four, eight, sixteen, thirtyTwo] = await blocksHelper.readWidths(
        concat(prefix, word),
        3,
      );

      expect(one).to.equal("0x01");
      expect(two).to.equal("0x0102");
      expect(four).to.equal("0x01020304");
      expect(eight).to.equal("0x0102030405060708");
      expect(sixteen).to.equal("0x0102030405060708090a0b0c0d0e0f10");
      expect(thirtyTwo).to.equal(word);
    });

    it("requires every power-of-two byte width at absolute calldata positions", async () => {
      const prefix = "0xaabbcc";
      const word = ethers.hexlify(Uint8Array.from({ length: 32 }, (_, i) => i + 1));
      const source = concat(prefix, word);
      const mismatch = `0xff${word.slice(4)}`;

      for (const width of [1, 2, 4, 8, 16, 32]) {
        await blocksHelper.expectWidth(source, 3, width, word);
        await expect(blocksHelper.expectWidth(source, 3, width, mismatch)).to.be.revertedWithCustomError(
          blocksHelper,
          "UnexpectedValue",
        );
      }
    });

    it("writeBalanceBlock round-trips", async () => {
      const data: string = await helper.testWriteBalanceBlock(asset, amount);
      expect(ethers.getBytes(data).length).to.equal(72);
      expect(data.slice(0, 10)).to.equal(Keys.Balance);
      expect(data.slice(10, 18)).to.equal("00000040");
      expect(await helper.testUnpackBalance(data)).to.deep.equal([asset, amount]);
    });

    it("represents debt as a liability-only position", async () => {
      const liability = ethers.zeroPadValue("0x02", 32);
      const data = encodeLiabilityPosition(liability, 300n);
      expect(data).to.equal(await helper.testWritePositionBlock(ethers.ZeroHash, 0n, liability, 300n));
      expect(await helper.testUnpackPosition(data)).to.deep.equal([
        ethers.ZeroHash, 0n, liability, 300n, ethers.ZeroHash,
      ]);
    });

    it("encodes empty blocks through factories, writers, and executions", async () => {
      const expected = encodeBlock(Keys.Balance, "0x");
      expect(await helper.testToEmptyBlock(Keys.Balance)).to.equal(expected);
      expect(await helper.testWriteEmptyBlock(Keys.Balance)).to.equal(expected);
      expect(await blocksHelper.executionOutputEmpty(Keys.Balance)).to.equal(expected);
    });

    it("position block round-trips through writers and decoders", async () => {
      const liability = ethers.zeroPadValue("0x02", 32);
      const positionAmount = 500n;
      const debt = 300n;
      const expected = encodePositionBlock(asset, positionAmount, liability, debt);

      expect(ethers.getBytes(expected).length).to.equal(168);
      expect(expected.slice(0, 10)).to.equal(Keys.Position);
      expect(expected.slice(10, 18)).to.equal("000000a0");
      expect(await helper.testWritePositionBlock(asset, positionAmount, liability, debt)).to.equal(expected);
      expect(await helper.testWritePositionStructBlock(asset, positionAmount, liability, debt)).to.equal(expected);
      expect(await helper.testToPositionBlock(asset, positionAmount, liability, debt)).to.equal(expected);
      expect(await blocksHelper.writePosition(5n, asset, positionAmount, liability, debt)).to.equal(
        ethers.concat([new Uint8Array(5), expected]),
      );
      expect(await blocksHelper.executionOutputPosition(asset, positionAmount, liability, debt)).to.equal(expected);
      expect(await blocksHelper.executionUnpackPosition(encodeContextBlock(ethers.ZeroHash, expected, "0x"))).to.deep.equal([
        asset, positionAmount, liability, debt, ethers.ZeroHash,
      ]);
      expect(await helper.testUnpackPosition(expected)).to.deep.equal([asset, positionAmount, liability, debt, ethers.ZeroHash]);
      expect(await helper.testUnpackPositionValue(expected)).to.deep.equal([asset, positionAmount, liability, debt, ethers.ZeroHash]);
      expect(await helper.testMemoryUnpackPosition(expected)).to.deep.equal([
        asset, positionAmount, liability, debt, ethers.ZeroHash,
      ]);
    });

    it("decodes all memory position struct fields and rejects malformed headers", async () => {
      const counterparty = encodeUserAccount("0x42");
      const liability = pad32(12n);
      const data = encodePositionBlock(asset, 123n, liability, 456n, counterparty);
      expect(await helper.testMemoryUnpackPositionValue(data))
        .to.deep.equal([asset, 123n, liability, 456n, counterparty]);
      for (const invalid of [
        concat(Keys.Balance, ethers.dataSlice(data, 4)),
        concat(ethers.dataSlice(data, 0, 4), "0x00000080", ethers.dataSlice(data, 8)),
        ethers.dataSlice(data, 0, 167),
        "0x",
      ]) {
        await expect(helper.testMemoryUnpackPositionValue(invalid))
          .to.be.revertedWithCustomError(helper, "InvalidBlock");
      }
    });

    it("rejects legacy position/debt encodings across decoders", async () => {
      const position = encodePositionBlock(asset, amount, ethers.ZeroHash, 0n);
      const invalid = [
        encodeBlock(Keys.Position, ethers.dataSlice(position, 8, 136)),
        encodeBlock(ethers.id("#debt").slice(0, 10), concat(pad32(asset), pad32(amount))),
      ];
      for (const data of invalid) {
        await expect(blocksHelper.unpackPosition(data)).to.be.revertedWithCustomError(blocksHelper, "InvalidBlock");
        await expect(helper.testMemoryUnpackPosition(data)).to.be.revertedWithCustomError(helper, "InvalidBlock");
        await expect(helper.testMemoryUnpackPositionValue(data)).to.be.revertedWithCustomError(helper, "InvalidBlock");
        await expect(helper.testUnpackPosition(data)).to.be.revertedWithCustomError(helper,
          ethers.dataLength(data) < 168 ? "OutOfBounds" : "InvalidBlock");
        await expect(blocksHelper.executionUnpackPosition(encodeContextBlock(ethers.ZeroHash, data, "0x"))).to.be.revertedWithCustomError(blocksHelper,
          ethers.dataLength(data) < 168 ? "OutOfBounds" : "InvalidBlock");
      }
      expect(await helper.testWritePositionCounterparty(ethers.ZeroHash))
        .to.equal(encodePositionBlock(ethers.ZeroHash, 0n, ethers.ZeroHash, 0n));
    });

    it("preserves nonzero counterparties through generic position codecs", async () => {
      const counterparty = pad32((0x03010200n << 224n) | 123n);
      const data = await helper.testWritePositionCounterparty(counterparty);
      expect(data).to.equal(encodePositionBlock(ethers.ZeroHash, 0n, ethers.ZeroHash, 0n, counterparty));
      const expected = [ethers.ZeroHash, 0n, ethers.ZeroHash, 0n, counterparty];
      expect(await blocksHelper.unpackPosition(data)).to.deep.equal(expected);
      expect(await helper.testUnpackPosition(data)).to.deep.equal(expected);
      expect(await helper.testUnpackPositionValue(data)).to.deep.equal(expected);
      expect(await helper.testMemoryUnpackPosition(data)).to.deep.equal(expected);
      expect(await helper.testMemoryUnpackPositionValue(data)).to.deep.equal(expected);
      expect(await blocksHelper.executionUnpackPosition(encodeContextBlock(ethers.ZeroHash, data, "0x"))).to.deep.equal(expected);
    });

    it("position decoder rejects another four-word block", async () => {
      const account = encodeUserAccount("0x03");
      const other = encodeUserAccount("0x04");
      await expect(blocksHelper.unpackPosition(encodeTxBlock(account, other, asset, amount)))
        .to.be.revertedWithCustomError(blocksHelper, "InvalidBlock");
    });

    it("hostAccountAsset block round-trips", async () => {
      const host = 1234n;
      const account = encodeUserAccount("0x03");
      const data = encodeHostAccountAssetBlock(host, account, asset);
      expect(ethers.getBytes(data).length).to.equal(104);
      expect(data.slice(0, 10)).to.equal(Keys.HostAccountAsset);
      expect(await helper.testUnpackHostAccountAsset(data)).to.deep.equal([host, account, asset]);
    });

    it("accountAsset block round-trips", async () => {
      const account = encodeUserAccount("0x03");
      const data = encodeAccountAssetBlock(account, asset);
      expect(ethers.getBytes(data).length).to.equal(72);
      expect(data.slice(0, 10)).to.equal(Keys.AccountAsset);
      expect(await helper.testUnpackAccountAsset(data)).to.deep.equal([account, asset]);
    });

    it("assetLiability block round-trips through factories, writers, and execution", async () => {
      const liability = ethers.zeroPadValue("0x44", 32);
      const data = encodeAssetLiabilityBlock(asset, liability);
      expect(ethers.getBytes(data).length).to.equal(72);
      expect(data.slice(0, 10)).to.equal(Keys.AssetLiability);
      expect(await blocksHelper.unpackAssetLiability(data)).to.deep.equal([asset, liability]);
      expect(await blocksHelper.createAssetLiability(asset, liability)).to.equal(data);
      expect(await blocksHelper.appendAssetLiability(asset, liability)).to.equal(data);
      expect(await blocksHelper.executionUnpackAssetLiability(data)).to.deep.equal([asset, liability]);
    });

    it("hostAsset block round-trips", async () => {
      const host = 1234n;
      const data = encodeHostAssetBlock(host, asset);
      expect(ethers.getBytes(data).length).to.equal(72);
      expect(data.slice(0, 10)).to.equal(Keys.HostAsset);
      expect(await helper.testUnpackHostAsset(data)).to.deep.equal([host, asset]);
      expect(await blocksHelper.unpackHostAsset(data)).to.deep.equal([host, asset]);
      expect(await blocksHelper.writeHostAsset(3n, host, asset)).to.equal(
        ethers.concat([new Uint8Array(3), data]),
      );
      expect(await blocksHelper.appendHostAsset(host, asset)).to.equal(data);
      expect(await blocksHelper.executionOutputHostAsset(host, asset)).to.equal(data);
    });

    it("writeCustodyBlock produces 104 bytes", async () => {
      const data: string = await helper.testWriteCustodyBlock(1234n, asset, amount);
      expect(ethers.getBytes(data).length).to.equal(104);
    });

    it("writeTxBlock round-trips", async () => {
      const from_ = encodeUserAccount("0x03");
      const to_ = encodeUserAccount("0x04");
      const data: string = await helper.testWriteTxBlock(from_, to_, asset, amount);
      expect(ethers.getBytes(data).length).to.equal(136);
      expect(await helper.testToTxValue(data)).to.deep.equal([from_, to_, asset, amount]);
    });

    it("transaction struct overload matches separate fields", async () => {
      const from_ = encodeUserAccount("0x03");
      const to_ = encodeUserAccount("0x04");
      const fields: string = await helper.testWriteTxBlock(from_, to_, asset, amount);
      const value: string = await helper.testWriteTxStructBlock(from_, to_, asset, amount);
      expect(value).to.equal(fields);
    });

    it("writeStringBlock round-trips UTF-8 payloads", async () => {
      const label = "credit account";
      const data: string = await stringHelper.testWriteStringBlock(label);
      expect(data).to.equal(encodeStringBlock(label));
      expect(data.slice(0, 10)).to.equal(Keys.String);
      expect(data.slice(10, 18)).to.equal("0000000e");
      expect(await stringHelper.testUnpackString(data)).to.deep.equal([label, BigInt(ethers.getBytes(data).length)]);
    });

    it("balance returns a valid encoded BALANCE block", async () => {
      const data: string = await helper.testToBalanceBlock(asset, amount);
      expect(ethers.getBytes(data).length).to.equal(72);
      expect(data.slice(0, 10)).to.equal(Keys.Balance);
      expect(await helper.testUnpackBalance(data)).to.deep.equal([asset, amount]);
    });

    it("amount returns a valid encoded AMOUNT block", async () => {
      const data: string = await helper.testToAmountBlock(asset, amount);
      expect(data).to.equal(encodeAmountBlock(asset, amount));
    });

    it("bootstrap returns a valid encoded BOOTSTRAP block", async () => {
      const budget = 19n;
      const data: string = await helper.testToBootstrapBlock(asset, amount, budget);
      expect(data).to.equal(encodeBootstrapBlock(asset, amount, budget));
      expect(await blocksHelper.unpackBootstrap(data)).to.deep.equal([asset, amount, budget]);
      expect(await helper.testUnpackBootstrap(data)).to.deep.equal([asset, amount, budget]);
    });

    it("writeBalance writes the specialized encoding at the requested offset", async () => {
      const offset = 5n;
      const data = await blocksHelper.writeBalance(offset, asset, amount);
      expect(data).to.equal(ethers.concat([new Uint8Array(Number(offset)), encodeBalanceBlock(asset, amount)]));
    });

    it("unpackBalance decodes a block from an absolute calldata position", async () => {
      expect(await blocksHelper.unpackBalance(encodeBalanceBlock(asset, amount)))
        .to.deep.equal([asset, amount]);
    });

    it("unpackBalance rejects the wrong key or payload length", async () => {
      await expect(blocksHelper.unpackBalance(encodeAmountBlock(asset, amount)))
        .to.be.revertedWithCustomError(blocksHelper, "InvalidBlock");
      await expect(blocksHelper.unpackBalance(encodeBlock(Keys.Balance, asset)))
        .to.be.revertedWithCustomError(blocksHelper, "InvalidBlock");
    });

    it("decodes every fixed-width block through its semantic helper", async () => {
      const account = encodeUserAccount("0x03");
      const other = encodeUserAccount("0x04");
      const host = 1234n;

      expect(await blocksHelper.unpackAccount(encodeAccountBlock(account))).to.equal(account);
      expect(await blocksHelper.unpackAsset(encodeAssetBlock(asset))).to.equal(asset);
      expect(await blocksHelper.unpackNode(encodeNodeBlock(host))).to.equal(host);
      expect(await blocksHelper.unpackStatus(encodeStatusBlock(7n))).to.equal(7n);
      expect(await blocksHelper.unpackAmount(encodeAmountBlock(asset, amount))).to.deep.equal([asset, amount]);
      expect(await blocksHelper.unpackBalance(encodeBalanceBlock(asset, amount))).to.deep.equal([asset, amount]);
      expect(await blocksHelper.unpackAssetLiability(encodeAssetLiabilityBlock(asset, other)))
        .to.deep.equal([asset, other]);
      expect(await blocksHelper.unpackAccountAsset(encodeAccountAssetBlock(account, asset)))
        .to.deep.equal([account, asset]);
      expect(await blocksHelper.unpackHostAsset(encodeHostAssetBlock(host, asset)))
        .to.deep.equal([host, asset]);

      expect(await blocksHelper.unpackAllocation(encodeAllocationBlock(host, asset, amount)))
        .to.deep.equal([host, asset, amount]);
      expect(await blocksHelper.unpackAllowance(encodeAllowanceBlock(host, asset, amount)))
        .to.deep.equal([host, asset, amount]);
      expect(await blocksHelper.unpackCustody(encodeCustodyBlock(host, asset, amount)))
        .to.deep.equal([host, asset, amount]);
      expect(await blocksHelper.unpackAccountAmount(encodeAccountAmountBlock(account, asset, amount)))
        .to.deep.equal([account, asset, amount]);
      expect(await blocksHelper.unpackHostAmount(
        encodeBlock(Keys.HostAmount, concat(pad32(host), pad32(asset), pad32(amount)))
      )).to.deep.equal([host, asset, amount]);
      expect(await blocksHelper.unpackHostAccountAsset(encodeHostAccountAssetBlock(host, account, asset)))
        .to.deep.equal([host, account, asset]);

      expect(await blocksHelper.unpackPosition(encodePositionBlock(asset, amount, other, 99n)))
        .to.deep.equal([asset, amount, other, 99n, ethers.ZeroHash]);
      expect(await blocksHelper.unpackTransaction(encodeTxBlock(account, other, asset, amount)))
        .to.deep.equal([account, other, asset, amount]);
      expect(await blocksHelper.unpackHostAccountAmount(
        encodeBlock(Keys.HostAccountAmount, concat(pad32(host), pad32(account), pad32(asset), pad32(amount)))
      )).to.deep.equal([host, account, asset, amount]);
    });

    it("custody returns a valid encoded CUSTODY block", async () => {
      const data: string = await helper.testToCustodyBlock(1234n, asset, amount);
      expect(ethers.getBytes(data).length).to.equal(104);
      expect(data.slice(0, 10)).to.equal(Keys.Custody);
    });

    it("transaction returns a valid encoded TRANSACTION block", async () => {
      const from_ = encodeUserAccount("0x03");
      const to_ = encodeUserAccount("0x04");
      const data: string = await helper.testToTransactionBlock(from_, to_, asset, amount);
      expect(ethers.getBytes(data).length).to.equal(136);
      expect(data.slice(0, 10)).to.equal(Keys.Transaction);
      expect(await helper.testToTxValue(data)).to.deep.equal([from_, to_, asset, amount]);
    });

    it("writeTransaction writes the specialized encoding at the requested offset", async () => {
      const from_ = encodeUserAccount("0x03");
      const to_ = encodeUserAccount("0x04");
      const offset = 5n;
      const data = await blocksHelper.writeTransaction(offset, from_, to_, asset, amount);
      expect(data).to.equal(ethers.concat([new Uint8Array(Number(offset)), encodeTxBlock(from_, to_, asset, amount)]));
    });

    it("writes every dynamic block at the requested offset", async () => {
      const offset = 5n;
      const raw = "0x0102030405";
      const cmd = 7n;
      const target = 7n;
      const resources = 11n;
      const account = encodeUserAccount("0x03");
      const state = encodeAssetBlock(asset);
      const input = "0xaabbcc";
      const namespace = pad32("0x99");
      const recoveryKey = pad32("0x77");
      const spec = exactSpec(Keys.Asset, 32);
      const expected = (block: string) =>
        ethers.concat([new Uint8Array(Number(offset)), block]);

      expect(await blocksHelper.writeList(offset, raw))
        .to.equal(expected(encodeListBlock(raw)));
      expect(await blocksHelper.writeBytes(offset, raw))
        .to.equal(expected(encodeBytesBlock(raw)));
      expect(await blocksHelper.writeString(offset, "rootzero"))
        .to.equal(expected(encodeStringBlock("rootzero")));
      expect(await blocksHelper.writeStep(offset, cmd, resources, input))
        .to.equal(expected(encodeStepBlock(cmd, resources, input)));
      expect(await blocksHelper.writeCall(offset, target, resources, raw))
        .to.equal(expected(encodeCallBlock(target, resources, raw)));
      expect(await blocksHelper.writeRelay(offset, target, resources, input))
        .to.equal(expected(encodeRelayBlock(ethers.concat([pad32(target), pad32(resources)]), input)));
      expect(await blocksHelper.writeDispatch(offset, target, resources, raw))
        .to.equal(expected(encodeDispatchBlock(target, resources, raw)));
      expect(await blocksHelper.writeContext(offset, account, state, input))
        .to.equal(expected(encodeContextBlock(account, state, input)));
      expect(await blocksHelper.writeRecover(offset, target, resources, recoveryKey, raw))
        .to.equal(expected(encodeRecoverBlock(target, resources, recoveryKey, raw)));
      expect(await blocksHelper.writeLabel(offset, namespace, "rootzero"))
        .to.equal(expected(encodeLabelBlock(namespace, "rootzero")));
      expect(await blocksHelper.writeSchema(offset, spec, "assets: bytes32 asset"))
        .to.equal(expected(encodeSchemaBlock(spec, "assets: bytes32 asset")));
    });

    it("unpacks dynamic leaf blocks using their absolute end positions", async () => {
      const raw = "0x0102030405";
      const text = "rootzero";
      const stringdata = ethers.hexlify(ethers.toUtf8Bytes(text));
      const list = encodeListBlock(raw);
      const data = encodeBytesBlock(raw);
      const string = encodeStringBlock(text);

      expect(await blocksHelper.unpackList(list))
        .to.deep.equal([raw, BigInt(ethers.getBytes(list).length)]);
      expect(await blocksHelper.unpackBytes(data))
        .to.deep.equal([raw, BigInt(ethers.getBytes(data).length)]);
      expect(await blocksHelper.unpackString(string))
        .to.deep.equal([stringdata, BigInt(ethers.getBytes(string).length)]);
    });

    it("rejects the wrong dynamic leaf key", async () => {
      await expect(blocksHelper.unpackBytes(encodeStringBlock("rootzero")))
        .to.be.revertedWithCustomError(blocksHelper, "InvalidBlock");
    });

    it("enters a spec at an absolute calldata position", async () => {
      const raw = "0x0102030405";
      const block = encodeBytesBlock(raw);
      const spec = exactSpec(Keys.Bytes, ethers.getBytes(raw).length);

      expect(await blocksHelper.headerAbsolute(block))
        .to.deep.equal([Keys.Bytes, BigInt(ethers.getBytes(raw).length)]);
      expect(await blocksHelper["headerAbsolute(bytes,bytes4)"](block, Keys.Bytes))
        .to.equal(BigInt(ethers.getBytes(raw).length));
      expect(await blocksHelper.enterAbsolute(block, spec))
        .to.deep.equal([8n, BigInt(ethers.getBytes(block).length)]);
      expect(await blocksHelper.enterSlice(block, spec))
        .to.deep.equal([8n, BigInt(ethers.getBytes(block).length), BigInt(ethers.getBytes(block).length)]);
    });

    it("descends into the first child while retaining the parent end", async () => {
      for (const raw of ["0x", "0x0102030405"]) {
        const child = encodeBytesBlock(raw);
        const siblings = encodeStringBlock("sibling");
        const parent = encodeListBlock(child, siblings);
        expect(await blocksHelper.descendAbsolute(
          parent,
          rangedSpec(Keys.List, 8, 0, 128),
          exactSpec(Keys.Bytes, ethers.dataLength(raw)),
        )).to.deep.equal([16n, BigInt(8 + ethers.dataLength(child)), BigInt(ethers.dataLength(parent))]);
      }
    });

    it("descend validates both parent and child specifications", async () => {
      const source = encodeListBlock(encodeBytesBlock("0x010203"));
      const parent = exactSpec(Keys.List, 11);
      const child = exactSpec(Keys.Bytes, 3);
      for (const [p, c] of [
        [exactSpec(Keys.String, 11), child],
        [exactSpec(Keys.List, 12), child],
        [parent, exactSpec(Keys.String, 3)],
        [parent, exactSpec(Keys.Bytes, 2)],
        [parent, rangedSpec(Keys.Bytes, 4, 0, 32)],
      ]) {
        await expect(blocksHelper.descendAbsolute(source, p, c))
          .to.be.revertedWithCustomError(blocksHelper, "InvalidBlock");
      }
    });

    it("descend leaves source bounds and child containment to the caller", async () => {
      const child = encodeBytesBlock("0x010203");
      // Parent declares only the child header; child declares three payload bytes.
      const source = encodeListBlock(ethers.dataSlice(child, 0, 8));
      expect(await blocksHelper.descendAbsolute(
        source, exactSpec(Keys.List, 8), exactSpec(Keys.Bytes, 3),
      )).to.deep.equal([16n, 19n, 16n]);
    });

    it("rejects absolute blocks outside the expected spec shape", async () => {
      const raw = "0x0102030405";
      const block = encodeBytesBlock(raw);

      await expect(blocksHelper.enterAbsolute(block, exactSpec(Keys.String, 5)))
        .to.be.revertedWithCustomError(blocksHelper, "InvalidBlock");
      await expect(blocksHelper.enterAbsolute(block, exactSpec(Keys.Bytes, 4)))
        .to.be.revertedWithCustomError(blocksHelper, "InvalidBlock");
      await expect(blocksHelper["headerAbsolute(bytes,bytes4)"](block, Keys.String))
        .to.be.revertedWithCustomError(blocksHelper, "InvalidBlock");
    });

    it("enters the first block directly from a calldata slice", async () => {
      const raw = "0x0102030405";
      const block = encodeBytesBlock(raw);
      const trailing = encodeStringBlock("rootzero");
      const spec = exactSpec(Keys.Bytes, ethers.getBytes(raw).length);

      expect(await blocksHelper.enterSlice(ethers.concat([block, trailing]), spec))
        .to.deep.equal([
          8n,
          BigInt(ethers.getBytes(block).length),
          BigInt(ethers.getBytes(block).length + ethers.getBytes(trailing).length),
        ]);
    });

    it("validates the spec when entering a calldata slice", async () => {
      const raw = "0x0102030405";
      const block = encodeBytesBlock(raw);

      await expect(blocksHelper.enterSlice(block, exactSpec(Keys.String, 5)))
        .to.be.revertedWithCustomError(blocksHelper, "InvalidBlock");
      await expect(blocksHelper.enterSlice(block, exactSpec(Keys.Bytes, 4)))
        .to.be.revertedWithCustomError(blocksHelper, "InvalidBlock");
    });

    it("leaves calldata-slice length validation to the caller", async () => {
      const raw = "0x0102030405";
      const block = encodeBytesBlock(raw);
      const spec = exactSpec(Keys.Bytes, ethers.getBytes(raw).length);

      expect(await blocksHelper.enterSlice(ethers.dataSlice(block, 0, 8), spec))
        .to.deep.equal([8n, BigInt(ethers.getBytes(block).length), 8n]);
    });

    it("requires an exact block to occupy the complete calldata slice", async () => {
      const raw = "0x0102030405";
      const block = encodeBytesBlock(raw);
      const spec = exactSpec(Keys.Bytes, ethers.getBytes(raw).length);

      expect(await blocksHelper.exactBlock(block, spec)).to.equal(8n);
      await expect(blocksHelper.exactBlock(ethers.concat([block, encodeStringBlock("x")]), spec))
        .to.be.revertedWithCustomError(blocksHelper, "InvalidBlock");
      await expect(blocksHelper.exactBlock(ethers.dataSlice(block, 0, 8), spec))
        .to.be.revertedWithCustomError(blocksHelper, "InvalidBlock");
    });

    it("enters after a bounded fixed prefix by spec or key", async () => {
      const block = encodeListBlock(ethers.hexlify(ethers.randomBytes(64)));
      const spec = exactSpec(Keys.List, 64);

      expect(await blocksHelper.enterAmountAbsolute(block, spec, 32n))
        .to.deep.equal([8n, 40n, 72n]);
      expect(await blocksHelper.enterKeyAmountAbsolute(block, Keys.List, 32n))
        .to.deep.equal([8n, 40n, 72n]);
      await expect(blocksHelper.enterAmountAbsolute(block, spec, 65n))
        .to.be.revertedWithCustomError(blocksHelper, "InvalidBlock");
      await expect(blocksHelper.enterKeyAmountAbsolute(block, Keys.List, 65n))
        .to.be.revertedWithCustomError(blocksHelper, "InvalidBlock");
    });

    it("stores the transaction header at the start of its word-aligned spec", async () => {
      const spec: string = await blocksHelper.transactionSpec();
      expect(spec.slice(0, 18)).to.equal(encodeTxBlock(ethers.ZeroHash, ethers.ZeroHash, ethers.ZeroHash, 0n).slice(0, 18));
    });

    it("derives fixed bounds and stores dynamic bounds in specs", async () => {
      expect(await blocksHelper.specRanges()).to.deep.equal([128n, 128n, 72n, 0n]);
    });

    it("stores allocation hints in three bytes", async () => {
      expect(await blocksHelper.specHint(0xffffff)).to.equal(0xffffffn);
      await expect(blocksHelper.specHint(0x1000000))
        .to.be.revertedWithCustomError(blocksHelper, "ValueOverflow");
    });

    it("label factory matches the canonical LABEL encoding", async () => {
      const namespace = pad32("0x1234");
      expect(await helper.testToLabelBlock(namespace, "rootzero"))
        .to.equal(encodeLabelBlock(namespace, "rootzero"));
    });

    it("action factory matches the canonical ACTION encoding", async () => {
      expect(await helper.testToActionBlock(4n)).to.equal(encodeActionBlock(4n));
    });

    it("publishes an action annotation", async () => {
      await expect(blocksHelper.publishAction(123n, 4n))
        .to.emit(blocksHelper, "Annotation")
        .withArgs(123n, encodeActionBlock(4n));
    });

    for (const account of [ethers.ZeroHash, encodeUserAccount("0x42"), pad32((0x03010200n << 224n) | 2n)]) {
      it(`encodes and publishes counterparty account ${account}`, async () => {
        const encoded = encodeCounterpartyBlock(account);
        expect(ethers.dataLength(encoded)).to.equal(40);
        expect(ethers.dataSlice(encoded, 8)).to.equal(account);
        expect(await helper.testToCounterpartyBlock(account)).to.equal(encoded);
        await expect(blocksHelper.publishCounterparty(123n, account))
          .to.emit(blocksHelper, "Annotation").withArgs(123n, encoded);
      });
    }

    it("leaves counterparty claim validation to consumers", async () => {
      const value = pad32(456n);
      await expect(blocksHelper.publishCounterparty(123n, value))
        .to.emit(blocksHelper, "Annotation")
        .withArgs(123n, encodeCounterpartyBlock(value));
    });

    it("schema factory matches the canonical SCHEMA encoding", async () => {
      const spec = exactSpec(Keys.Asset, 32);
      expect(await helper["testToSchemaBlock(uint256,string)"](spec, "assets: bytes32 asset"))
        .to.equal(encodeSchemaBlock(spec, "assets: bytes32 asset"));
      expect(await helper["testToSchemaBlock(uint256,string)"](spec, "bytes32 asset"))
        .to.equal(encodeSchemaBlock(spec, "bytes32 asset"));
    });

    it("creates exact specs from a numeric key and size", async () => {
      const key = 1n;
      const size = 64n;
      const spec = (key << 224n) | (size << 192n) | (size << 160n) | (size << 136n);
      expect(await blocksHelper.exactSpec(key, size)).to.equal(spec);
    });

    it("derives initial byte capacity from block counts and hints", async () => {
      expect(await blocksHelper.blockCapacity()).to.equal(6n * 72n);
    });

    it("initializes execution output capacity from the input run", async () => {
      const amountSpec = exactSpec(Keys.Amount, 64);
      const balanceSpec = exactSpec(Keys.Balance, 64);
      const input = concat(
        encodeAmountBlock(asset, 1n),
        encodeAmountBlock(asset, 2n),
        encodeAmountBlock(asset, 3n),
        encodeAmountBlock(asset, 4n),
      );

      expect(await blocksHelper.executionWriterHint(encodeContextBlock(ethers.ZeroHash, "0x", input), 0, amountSpec, balanceSpec))
        .to.equal(4n * 72n);
    });

    it("uses state before input as the output hint source", async () => {
      const balanceSpec = exactSpec(Keys.Balance, 64);
      const amountSpec = exactSpec(Keys.Amount, 64);
      const positionSpec = exactSpec(Keys.Position, 160);
      const state = encodeBalanceBlock(asset, 1n);
      const input = concat(
        encodeAmountBlock(asset, 2n),
        encodeAmountBlock(asset, 3n),
      );

      expect(
        await blocksHelper.executionWriterHint(encodeContextBlock(ethers.ZeroHash, state, input),
          balanceSpec,
          amountSpec,
          positionSpec,
        ),
      ).to.equal(168n);
    });

    it("uses state as the output-hint source when descriptor input is empty", async () => {
      const balanceSpec = exactSpec(Keys.Balance, 64);
      const amountSpec = exactSpec(Keys.Amount, 64);
      const state = concat(
        encodeBalanceBlock(asset, 1n),
        encodeBalanceBlock(asset, 2n),
        encodeBalanceBlock(asset, 3n),
      );

      expect(await blocksHelper.executionWriterHint(encodeContextBlock(ethers.ZeroHash, state, "0x"), balanceSpec, 0, amountSpec))
        .to.equal(3n * 72n);
    });

    it("precomputes absent sources and maximum block sizes without truncation", async () => {
      const spec = rangedSpec(Keys.Bytes, 0, 0, 0xffffff);
      const descriptor = await blocksHelper.describeSpecs(0, spec, spec);
      const size = 0xffffffn + 8n;
      expect((descriptor >> 96n) & 0xffffffffn).to.equal(size);
      expect((descriptor >> 64n) & 0xffffffffn).to.equal(size);
      expect((descriptor >> 128n) & 0xffffffffn).to.equal(BigInt(Keys.Bytes));
      expect(descriptor & ((1n << 64n) - 1n)).to.equal(2n << 48n);
      const noSource = await blocksHelper.describeSpecs(0, 0, exactSpec(Keys.Balance, 64));
      expect((noSource >> 96n) & 0xffffffffffffffffn).to.equal(0n);
      expect((noSource >> 64n) & 0xffffffffn).to.equal(72n);
      expect(await blocksHelper.executionWriterHint(encodeContextBlock(ethers.ZeroHash, "0x", "0x"), 0, 0, exactSpec(Keys.Balance, 64)))
        .to.equal(72n);
    });

    it("uses divisible byte estimates and scans nondivisible variable blocks", async () => {
      const spec = rangedSpec(Keys.Bytes, 0, 0, 128);
      const output = exactSpec(Keys.Balance, 64);
      // Seventeen empty blocks occupy one hinted block: deliberately underestimate.
      const small = concat(...Array.from({ length: 17 }, () => encodeBytesBlock("0x")));
      expect(await blocksHelper.executionWriterHint(encodeContextBlock(ethers.ZeroHash, "0x", small), 0, spec, output))
        .to.equal(72n);
      // Three encoded 264-byte blocks do not divide by the hinted 136-byte block.
      const large = concat(...Array.from({ length: 3 }, () => encodeBytesBlock("0x" + "a5".repeat(256))));
      expect(await blocksHelper.executionWriterHint(encodeContextBlock(ethers.ZeroHash, "0x", large), 0, spec, output))
        .to.equal(3n * 72n);
      expect(await blocksHelper.executionWriterHint(encodeContextBlock(ethers.ZeroHash, small, "0x"), spec, 0, output))
        .to.equal(72n);
      // Declared state remains the selected source even when empty.
      expect(await blocksHelper.executionWriterHint(encodeContextBlock(ethers.ZeroHash, "0x", small), spec, spec, output))
        .to.equal(0n);
    });

    it("packs complete descriptor metadata without exposing field accessors", async () => {
      const expected =
        (BigInt(Keys.Balance) << 224n) |
        (BigInt(Keys.Asset) << 192n) |
        (BigInt(Keys.Amount) << 160n) |
        (BigInt(Keys.Balance) << 128n) |
        (72n << 96n) | (72n << 64n) | (64n << 56n) | (3n << 48n) |
        3n;

      expect(await blocksHelper.descriptorWord()).to.equal(expected);
    });

    it("precomputes every combination of declared lanes", async () => {
      for (const state of [0n, exactSpec(Keys.Balance, 64)]) {
        for (const input of [0n, exactSpec(Keys.Amount, 64)]) {
          const descriptor = await blocksHelper.describeSpecs(state, input, 0);
          const lanes = (state === 0n ? 0n : 1n) | (input === 0n ? 0n : 2n);
          expect((descriptor >> 48n) & 0xffn).to.equal(lanes);
          expect(descriptor & ((1n << 48n) - 1n)).to.equal(0n);
        }
      }
    });

    it("opens descriptor state and input cursors with initialized writers", async () => {
      const [stateCursor, stateWriter, inputCursor, inputWriter] =
        await blocksHelper.descriptorOpens(encodeContextBlock(ethers.ZeroHash, "0x1234", "0x"), "0xaabbcc");

      expect(((stateCursor >> 96n) & 0xffffffffn) - ((stateCursor >> 64n) & 0xffffffffn)).to.equal(2n);
      expect(stateCursor >> 128n).to.equal(3n);
      expect(((inputCursor >> 32n) & 0xffffffffn) - (inputCursor & 0xffffffffn)).to.equal(3n);
      expect(inputCursor >> 64n).to.equal(2n << 64n);
      expect((stateWriter >> 32n) & 0xffffffffn).to.equal(0n);
      expect(stateWriter >> 64n).to.equal(0n);
      expect((inputWriter >> 32n) & 0xffffffffn).to.equal(0n);
      expect(inputWriter >> 64n).to.equal(0n);
    });

    it("enters an input parent while preserving execution state", async () => {
      const stateAsset = ethers.zeroPadValue("0x31", 32);
      const inputAsset = ethers.zeroPadValue("0x32", 32);
      const state = encodeBalanceBlock(stateAsset, 41n);
      const input = encodeListBlock(encodeAmountBlock(inputAsset, 42n));

      expect(await blocksHelper.executionEnterAmount(encodeContextBlock(ethers.ZeroHash, state, input)))
        .to.deep.equal([stateAsset, 41n, inputAsset, 42n]);
    });

    it("keeps state/input traversal gas within one percent of tagged relative cursors", async () => {
      const state = encodeBalanceBlock(ethers.zeroPadValue("0x31", 32), 41n);
      const input = encodeListBlock(encodeAmountBlock(ethers.zeroPadValue("0x32", 32), 42n));

      expect(await blocksHelper.executionEnterAmount(encodeContextBlock(ethers.ZeroHash, state, input)))
        .to.deep.equal(await blocksHelper.legacyExecutionEnterAmount(encodeContextBlock(ethers.ZeroHash, state, input)));
      const specialized = await blocksHelper.executionEnterAmount.estimateGas(encodeContextBlock(ethers.ZeroHash, state, input));
      const legacy = await blocksHelper.legacyExecutionEnterAmount.estimateGas(encodeContextBlock(ethers.ZeroHash, state, input));
      // Whole-call estimates include selector dispatch and cursor initialization.
      // Allow small compiler/layout changes while detecting a material regression.
      expect(specialized * 100n).to.be.lessThan(legacy * 101n);
    });

    it("next32 consumes raw words from an entered execution parent", async () => {
      const first = ethers.zeroPadValue("0x41", 32);
      const second = ethers.zeroPadValue("0x42", 32);
      const input = encodeListBlock(first, second);

      expect(await blocksHelper.executionEnterWords(input)).to.deep.equal([first, second]);
    });

    it("consumes power-of-two byte widths from an entered execution parent", async () => {
      const fields = [
        "0x01",
        "0x0203",
        "0x04050607",
        "0x08090a0b0c0d0e0f",
        "0x101112131415161718191a1b1c1d1e1f",
        "0x202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f",
      ];
      const input = encodeListBlock(...fields);

      expect(await blocksHelper.executionEnterSized(input)).to.deep.equal(fields);
    });

    it("copies calldata payloads through factories, writers, and executions", async () => {
      for (const value of ["0x", "0x123456"]) {
        const expected = concat(
          encodeBlock(localKey(1), value),
          encodeListBlock(value),
          encodeBytesBlock(value),
          encodeStepBlock(1n, 2n, value),
          encodeCallBlock(3n, 4n, value),
          encodeRelayBlock(ethers.concat([pad32(5n), pad32(6n)]), value),
          encodeDispatchBlock(7n, 8n, value),
          encodeContextBlock(ethers.zeroPadValue("0x09", 32), value, value),
          encodeRecoverBlock(10n, 11n, ethers.zeroPadValue("0x0c", 32), value),
        );

        expect(await blocksHelper.factoryCopies(value)).to.equal(expected);
        expect(await blocksHelper.writerCopies(value)).to.equal(expected);
        expect(await blocksHelper.executionCopies(value)).to.equal(expected);
      }
    });

    it("copies raw calldata into buffers and writers", async () => {
      for (const value of ["0x", "0x123456"]) {
        expect(await blocksHelper.writerCopy(value)).to.equal(concat("0xaa", value, "0xbb"));
      }

      expect(await blocksHelper.bufferCopy(7, 2, "0x123456"))
        .to.deep.equal(["0x00001234560000", 5n]);
      await expect(blocksHelper.bufferCopy(4, 2, "0x123456"))
        .to.be.revertedWithCustomError(blocksHelper, "BufferOverflow");
    });

    it("copies calldata strings through factories, writers, and executions", async () => {
      for (const value of ["", "rootzero ⚡"]) {
        const expected = encodeStringBlock(value);
        expect(await blocksHelper.stringCopies(value)).to.deep.equal([expected, expected, expected]);
      }
    });

    it("text returns a valid encoded STRING block", async () => {
      const label = "relayBalancePayable";
      const data: string = await stringHelper.testToStringBlock(label);
      expect(data).to.equal(encodeStringBlock(label));
      expect(data.slice(0, 10)).to.equal(Keys.String);
    });

    it("finish returns empty bytes when writer is unused", async () => {
      expect(await helper.testWriterFinishEmpty()).to.equal("0x");
    });

    it("finish truncates to actual written length", async () => {
      const data: string = await helper.testWriterFinish(asset, amount);
      expect(ethers.getBytes(data).length).to.equal(72);
    });

    it("allocates an initialized writer on its first write", async () => {
      const data: string = await blocksHelper.lazyBalance(asset, amount);
      expect(data).to.equal(encodeBalanceBlock(asset, amount));
    });

    it("returns an unallocated writer for a zero block count", async () => {
      expect(await blocksHelper.emptyWriter()).to.deep.equal([0n, 0n, 0n]);
    });

    it("lazily allocates a buffer with packed position and capacity", async () => {
      expect(await blocksHelper.reserveBuffer(33, 2, 32))
        .to.deep.equal([0n, 2n, 33n, 96n]);
    });

    it("uses touch for capacity and advance for the logical position", async () => {
      expect(await blocksHelper.reserveBuffer(16, 2, 32))
        .to.deep.equal([0n, 2n, 32n, 64n]);
    });

    it("grows an allocated buffer and preserves its written prefix", async () => {
      const first = ethers.zeroPadValue("0x11", 32);
      const second = ethers.zeroPadValue("0x22", 32);
      expect(await blocksHelper.growBuffer(first, second))
        .to.equal(concat(first, second));
    });

    it("grows every buffer beyond its initial capacity", async () => {
      expect(await blocksHelper.reserveBuffer(8, 16, 16))
        .to.deep.equal([0n, 16n, 16n, 64n]);
    });

    it("opens, spends, drains, and detaches standalone value budgets", async () => {
      const resources = (123n << 128n) | 3n;
      expect(await blocksHelper.budgetUseResourceValue.staticCall(resources, { value: 5n }))
        .to.deep.equal([3n, 2n]);
      expect(await blocksHelper.budgetUseValue.staticCall(3n, { value: 5n }))
        .to.deep.equal([3n, 2n]);
      expect(await blocksHelper.budgetAddValue(2n, 3n)).to.equal(5n);
      expect(await blocksHelper.executionAddToBudget(2n, 3n)).to.equal(5n);
      expect(await blocksHelper.budgetDrain.staticCall({ value: 5n }))
        .to.deep.equal([5n, 0n]);
      expect(await blocksHelper.takeBudget.staticCall({ value: 5n }))
        .to.deep.equal([0n, 5n]);
      expect(await blocksHelper.drainBudget.staticCall({ value: 5n }))
        .to.deep.equal([0n, 5n]);
      await expect(blocksHelper.budgetUseResourceValue.staticCall(6n, { value: 5n }))
        .to.be.revertedWithCustomError(blocksHelper, "InsufficientValue");
      await expect(blocksHelper.budgetUseValue.staticCall(1n << 128n))
        .to.be.revertedWithCustomError(blocksHelper, "InsufficientValue");
      for (const addValue of [
        () => blocksHelper.budgetAddValue(ethers.MaxUint256, 1n),
        () => blocksHelper.executionAddToBudget(ethers.MaxUint256, 1n),
      ]) {
        let overflowed = false;
        try {
          await addValue();
        } catch {
          overflowed = true;
        }
        expect(overflowed).to.equal(true);
      }
    });

    it("grows when appending past initial logical writer capacity", async () => {
      const block = encodeBlock("0x00000001", asset);
      expect(await blocksHelper.growSecond32(asset)).to.equal(concat(block, block));
    });

    it("rejects a payload that does not match a fixed spec", async () => {
      const oversized = ethers.concat([asset, asset]);
      await expect(blocksHelper.rejectOversizedDynamic(oversized))
        .to.be.revertedWithCustomError(blocksHelper, "InvalidSpec");
    });

    it("rejects dynamic payloads outside their spec range", async () => {
      await expect(blocksHelper.rejectOutOfRange("0x01"))
        .to.be.revertedWithCustomError(blocksHelper, "InvalidSpec");
      await expect(blocksHelper.rejectOutOfRange("0x0102030405"))
        .to.be.revertedWithCustomError(blocksHelper, "InvalidSpec");
    });
  });

  describe("Memory", () => {
    const asset = ethers.zeroPadValue("0xaa", 32);
    const otherAsset = ethers.zeroPadValue("0xbb", 32);
    const from = encodeUserAccount("0x01");
    const to = encodeUserAccount("0x02");

    it("unpacks a fixed-stride balance", async () => {
      const source = encodeBalanceBlock(asset, 123n);
      expect(await helper.testMemoryUnpackBalance(source)).to.deep.equal([
        asset,
        123n,
      ]);
    });

    it("unpacks a fixed-stride transaction", async () => {
      const source = encodeTxBlock(from, to, asset, 456n);
      expect(await helper.testMemoryUnpackTransaction(source)).to.deep.equal([
        from,
        to,
        asset,
        456n,
      ]);
    });

    it("unpacks sequential fixed-stride blocks", async () => {
      const source = concat(
        encodeBalanceBlock(asset, 123n),
        encodeBalanceBlock(otherAsset, 456n),
      );
      expect(await helper.testMemoryUnpackTwoBalances(source)).to.deep.equal([
        asset,
        123n,
        otherAsset,
        456n,
      ]);
    });

    it("rejects a block with the wrong key", async () => {
      await expect(helper.testMemoryUnpackBalance(encodeAmountBlock(asset, 123n)))
        .to.be.revertedWithCustomError(helper, "InvalidBlock");
    });

    it("rejects a wrong key later in a fixed-stride stream", async () => {
      const source = concat(
        encodeBalanceBlock(asset, 123n),
        encodeAmountBlock(otherAsset, 456n),
      );
      await expect(helper.testMemoryUnpackTwoBalances(source))
        .to.be.revertedWithCustomError(helper, "InvalidBlock");
    });

    it("rejects a payload below the minimum length", async () => {
      const source = encodeBlock(Keys.Balance, asset);
      await expect(helper.testMemoryUnpackBalance(source))
        .to.be.revertedWithCustomError(helper, "InvalidBlock");
    });

    it("rejects a payload above the maximum length", async () => {
      const source = encodeBlock(Keys.Balance, ethers.concat([asset, asset, asset]));
      await expect(helper.testMemoryUnpackBalance(source))
        .to.be.revertedWithCustomError(helper, "InvalidBlock");
    });

    it("rejects a truncated header", async () => {
      const source = ethers.dataSlice(encodeBalanceBlock(asset, 123n), 0, 7);
      await expect(helper.testMemoryUnpackBalance(source))
        .to.be.revertedWithCustomError(helper, "InvalidBlock");
    });

    it("rejects a truncated payload", async () => {
      const complete = ethers.getBytes(encodeBalanceBlock(asset, 123n));
      const source = ethers.hexlify(complete.slice(0, -1));
      await expect(helper.testMemoryUnpackBalance(source))
        .to.be.revertedWithCustomError(helper, "InvalidBlock");
    });
  });

  describe("Cursor helpers", () => {
    const asset = ethers.zeroPadValue("0xaa", 32);
    const otherAsset = ethers.zeroPadValue("0xbb", 32);
    const amount = 9999n;

    it("packs consumer flags directly above cursor bounds", async () => {
      const [cur, flags] = await helper.testSpanMeta(0x56);

      expect(cur).to.equal(0x56n << 64n);
      expect(flags).to.equal(0x56n);
    });

    it("returns the unread absolute cursor bounds", async () => {
      expect(await helper.testCursorBounds()).to.deep.equal([15n, 30n]);
    });

    it("returns calldata bounds for empty and whole-block streams", async () => {
      for (const size of [40, 168]) {
        for (const count of [0, 1, 3]) {
          const source = ethers.hexlify(new Uint8Array(size * count));
          // The selector, two arguments, and bytes length precede the payload.
          expect(await helper.testCalldataBounds(source, size))
            .to.deep.equal([100n, 100n + BigInt(size * count)]);
        }
      }
    });

    it("rejects partial calldata blocks at either side of a complete block", async () => {
      for (const size of [40, 168]) {
        for (const length of [1, size - 1, size + 1, size * 2 - 1]) {
          await expect(helper.testCalldataBounds(ethers.hexlify(new Uint8Array(length)), size))
            .to.be.revertedWithCustomError(helper, "InvalidBlock");
        }
      }
    });

    it("advances packed cursors while returning the pre-advance absolute position", async () => {
      expect(await helper.testCursorNavigation(100n, 10n, 3n, 4n))
        .to.deep.equal([7n, 103n, true]);
      expect(await helper.testCursorNavigation(100n, 10n, 3n, 7n))
        .to.deep.equal([10n, 103n, false]);
      await expect(helper.testCursorNavigation(100n, 10n, 3n, 8n))
        .to.be.revertedWithCustomError(helper, "OutOfBounds");
    });

    it("allows cursor capacity to shrink to its position but not below it", async () => {
      expect(await helper.testCursorResize(10n, 6n, 6n)).to.deep.equal([6n, 6n]);
      expect(await helper.testCursorResize(10n, 6n, 20n)).to.deep.equal([6n, 20n]);
      await expect(helper.testCursorResize(10n, 6n, 5n))
        .to.be.revertedWithCustomError(helper, "OutOfBounds");
    });

    it("open(source) creates an cursor over the complete source", async () => {
      const a = encodeAmountBlock(asset, 1n);
      const b = encodeBalanceBlock(asset, 2n);
      const source = concat(a, b);
      const [sourceStart, pos, end, flags] = await helper.testOpen(source);
      expect(pos).to.equal(sourceStart);
      expect(end - pos).to.equal(BigInt(ethers.getBytes(source).length));
      expect(flags).to.equal(0n);
    });

    it("open(source) accepts an empty source", async () => {
      const [sourceStart, pos, end, flags] = await helper.testOpen("0x");
      expect(pos).to.equal(sourceStart);
      expect(end).to.equal(pos);
      expect(flags).to.equal(0n);
    });

    it("close succeeds after the complete decoder source is consumed", async () => {
      const source = encodeAmountBlock(asset, 1n);
      expect(await helper.testClose(source, ethers.getBytes(source).length)).to.equal(true);
    });

    it("close rejects unread decoder data", async () => {
      const source = encodeAmountBlock(asset, 1n);
      await expect(helper.testClose(source, 0n))
        .to.be.revertedWithCustomError(helper, "UnconsumedData");
    });

    it("peek returns the next key and payload length", async () => {
      const source = encodeBalanceBlock(asset, amount);
      expect(await helper.testPeek(source, 0n)).to.deep.equal([Keys.Balance, 64n]);
    });

    it("enter advances into a parent payload so child blocks can be unpacked", async () => {
      const child = encodeAmountBlock(asset, amount);
      const source = encodeListBlock(child);

      expect(await helper.testEnterAmount(source, exactSpec(Keys.List, ethers.getBytes(child).length)))
        .to.deep.equal([
          asset,
          amount,
          BigInt(ethers.getBytes(source).length),
          BigInt(ethers.getBytes(source).length),
        ]);
    });

    it("next32 consumes raw words from an entered decoder parent", async () => {
      const first = ethers.zeroPadValue("0x51", 32);
      const second = ethers.zeroPadValue("0x52", 32);
      const source = encodeListBlock(first, second);

      expect(await helper.testEnterWords(source, exactSpec(Keys.List, 64)))
        .to.deep.equal([first, second]);
    });

    it("consumes power-of-two byte widths from an entered decoder parent", async () => {
      const fields = [
        "0x01",
        "0x0203",
        "0x04050607",
        "0x08090a0b0c0d0e0f",
        "0x101112131415161718191a1b1c1d1e1f",
        "0x202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f",
      ];
      const source = encodeListBlock(...fields);

      expect(await helper.testEnterSized(source, exactSpec(Keys.List, 63)))
        .to.deep.equal(fields);
    });

    it("enter validates the parent specification", async () => {
      const child = encodeAmountBlock(asset, amount);
      const source = encodeListBlock(child);

      await expect(helper.testEnterAmount(source, exactSpec(Keys.Bytes, ethers.getBytes(child).length)))
        .to.be.revertedWithCustomError(helper, "InvalidBlock");
    });

    it("enter advances over a fixed parent prefix without crossing its payload", async () => {
      const parent = encodeListBlock(ethers.hexlify(ethers.randomBytes(64)));
      const source = concat(parent, encodeAssetBlock(asset));
      const spec = exactSpec(Keys.List, 64);

      expect(await helper.testEnterAdvance(source, spec, 32n)).to.deep.equal([8n, 40n, 72n]);
      expect(await helper.testEnterKeyAdvance(source, Keys.List, 32n)).to.deep.equal([8n, 40n, 72n]);
      expect(await blocksHelper.executionEnterKeyAdvance(source, Keys.List, 32n))
        .to.deep.equal([8n, 40n, 72n]);
      await expect(helper.testEnterAdvance(source, spec, 65n))
        .to.be.revertedWithCustomError(helper, "InvalidBlock");
      await expect(helper.testEnterKeyAdvance(source, Keys.List, 65n))
        .to.be.revertedWithCustomError(helper, "InvalidBlock");
      await expect(blocksHelper.executionEnterKeyAdvance(source, Keys.List, 65n))
        .to.be.revertedWithCustomError(blocksHelper, "InvalidBlock");
    });

    it("reports the absolute position separately from advancing over raw bytes", async () => {
      const first = ethers.zeroPadValue("0x41", 32);
      const second = ethers.zeroPadValue("0x42", 32);

      expect(await helper.testAdvance(concat(first, second), 32n)).to.deep.equal([0n, 32n, first]);
      await expect(helper.testAdvance(first, 33n)).to.be.revertedWithCustomError(helper, "OutOfBounds");

      const input = encodeListBlock(first, second);
      expect(await blocksHelper.executionAdvance(input, 64n)).to.deep.equal([8n, first, true]);
      await expect(blocksHelper.executionAdvance(input, 65n))
        .to.be.revertedWithCustomError(blocksHelper, "OutOfBounds");
    });

    it("takes raw bytes and returns their starting absolute position", async () => {
      const first = ethers.zeroPadValue("0x41", 32);
      const second = ethers.zeroPadValue("0x42", 32);

      expect(await helper.testTakeRaw(concat(first, second), 32n)).to.deep.equal([0n, 32n, first]);
      await expect(helper.testTakeRaw(first, 33n)).to.be.revertedWithCustomError(helper, "OutOfBounds");

      const input = encodeListBlock(first, second);
      expect(await blocksHelper.executionTake(input, 64n)).to.deep.equal([8n, first, true]);
      await expect(blocksHelper.executionTake(input, 65n))
        .to.be.revertedWithCustomError(blocksHelper, "OutOfBounds");
    });

    it("past reports the position immediately after the current block without advancing", async () => {
      const source = encodeBalanceBlock(asset, amount);
      expect(await helper.testPastCurrent(source)).to.equal(72n);
    });

    it("isAt returns true for a matching well-formed block at the current cursor position", async () => {
      const source = encodeBalanceBlock(asset, amount);
      expect(await helper.testIsAtCurrent(source, Keys.Balance)).to.equal(true);
    });

    it("isAt returns false when the key does not match", async () => {
      const source = encodeBalanceBlock(asset, amount);
      expect(await helper.testIsAtCurrent(source, Keys.Amount)).to.equal(false);
    });

    it("isAt returns true for a truncated block when the current header key matches", async () => {
      const source = "0x" + Keys.Balance.slice(2) + "00000040";
      expect(await helper.testIsAtCurrent(source, Keys.Balance)).to.equal(true);
    });

    it("detects an empty block without consuming it", async () => {
      const empty = encodeBlock(Keys.Balance, "0x");
      expect(await helper.testIsEmptyCurrent(empty, Keys.Balance)).to.equal(true);
      expect(await helper.testIsEmptyCurrent(empty, Keys.Amount)).to.equal(false);
      expect(await helper.testIsEmptyCurrent(encodeBalanceBlock(asset, amount), Keys.Balance)).to.equal(false);
      expect(await helper.testIsEmptyCurrent(Keys.Balance, Keys.Balance)).to.equal(false);
    });

    it("conditionally consumes an empty block header", async () => {
      const empty = encodeBlock(Keys.Balance, "0x");
      const balance = encodeBalanceBlock(asset, amount);
      expect(await helper.testTryConsumeEmpty(empty, Keys.Balance)).to.deep.equal([true, 8n, false]);
      expect(await helper.testTryConsumeEmpty(empty, Keys.Amount)).to.deep.equal([false, 0n, true]);
      expect(await helper.testTryConsumeEmpty(balance, Keys.Balance)).to.deep.equal([false, 0n, true]);

      const malformed = "0x" + Keys.Balance.slice(2) + "00000040";
      await expect(helper.testTryConsumeEmpty(malformed, Keys.Balance))
        .to.be.revertedWithCustomError(helper, "MalformedBlocks");
      await expect(helper.testUnpackBalance(empty))
        .to.be.revertedWithCustomError(helper, "OutOfBounds");
    });

    it("uses less gas than the removed relative generic cursor", async () => {
      const source = concat(
        encodeBytesBlock("0x0102"),
        encodeBytesBlock("0x030405"),
        encodeBytesBlock("0x06070809"),
      );

      const absolute = await helper.absoluteCursorBytes.estimateGas(source);
      const relative = await helper.relativeCursorBytes.estimateGas(source);
      expect(absolute).to.be.lessThan(relative);
    });

    it("detects and consumes empty blocks through execution input", async () => {
      const empty = encodeBlock(Keys.Balance, "0x");
      expect(await blocksHelper.executionIsEmpty(empty, exactSpec(Keys.Balance, 64), Keys.Balance))
        .to.equal(true);
      expect(await blocksHelper.executionTryConsumeEmpty(empty, exactSpec(Keys.Balance, 64), Keys.Balance))
        .to.deep.equal([true, false]);
      expect(await blocksHelper.executionTryConsumeEmpty(empty, exactSpec(Keys.Balance, 64), Keys.Amount))
        .to.deep.equal([false, true]);
      expect(
        await blocksHelper.executionTryConsumeEmpty(
          encodeBalanceBlock(asset, amount),
          exactSpec(Keys.Balance, 64),
          Keys.Balance,
        ),
      ).to.deep.equal([false, true]);
    });

    it("hasAt checks a block key at an arbitrary source position", async () => {
      const a = encodeAmountBlock(asset, 1n);
      const b = encodeBalanceBlock(asset, 2n);
      const source = concat(a, b);
      const i = BigInt(ethers.getBytes(a).length);
      expect(await helper.testHasAt(source, i, Keys.Balance)).to.equal(true);
      expect(await helper.testHasAt(source, i, Keys.Amount)).to.equal(false);
      expect(await helper.testHasAt(source, BigInt(ethers.getBytes(source).length), Keys.Balance)).to.equal(false);
    });

    it("run counts consecutive matching blocks without advancing", async () => {
      const first = encodeAmountBlock(asset, 1n);
      const second = encodeAmountBlock(asset, 2n);
      const balance = encodeBalanceBlock(asset, 3n);
      const source = concat(first, second, balance);
      const balanceAt = BigInt(ethers.getBytes(first).length + ethers.getBytes(second).length);

      expect(await helper.testRun(source, 0n, Keys.Amount)).to.deep.equal([2n, 0n]);
      expect(await helper.testRun(source, 0n, Keys.Balance)).to.deep.equal([0n, 0n]);
      expect(await helper.testRun(source, balanceAt, Keys.Balance)).to.deep.equal([1n, balanceAt]);
    });

    it("runCount cheaply counts complete matching blocks for hints", async () => {
      const first = encodeAmountBlock(asset, 1n);
      const second = encodeAmountBlock(asset, 2n);
      const amounts = concat(first, second);
      const source = concat(amounts, encodeBalanceBlock(asset, 3n));

      expect(await helper.testRunCount(source, 0n, Keys.Amount)).to.equal(2n);
      expect(await helper.testRunCount(source, 0n, Keys.Balance)).to.equal(0n);

      const truncated = concat(first, "0x" + Keys.Amount.slice(2) + "00000040");
      expect(await helper.testRunCount(truncated, 0n, Keys.Amount)).to.equal(1n);
    });

    it("exact run requires every source block to have the expected key", async () => {
      const first = encodeAmountBlock(asset, 1n);
      const second = encodeAmountBlock(asset, 2n);
      const amounts = concat(first, second);

      expect(await helper.testRunExact(amounts, Keys.Amount))
        .to.deep.equal([2n, BigInt(ethers.getBytes(amounts).length)]);

      await expect(helper.testRunExact(concat(amounts, encodeBalanceBlock(asset, 3n)), Keys.Amount))
        .to.be.revertedWithCustomError(helper, "InvalidBlock");
    });

    it("run rejects a matching block that exceeds the cursor boundary", async () => {
      const truncated = "0x" + Keys.Amount.slice(2) + "00000040";

      await expect(helper.testRun(truncated, 0n, Keys.Amount))
        .to.be.revertedWithCustomError(helper, "MalformedBlocks");
    });

    it("slice creates a subcursor over the requested range", async () => {
      const a = encodeAssetBlock(asset);
      const b = encodeAccountBlock(encodeUserAccount("0x12"));
      const source = concat(a, b);
      const from = BigInt(ethers.getBytes(a).length);
      const to = BigInt(ethers.getBytes(source).length);
      const [offset, i, len] = await helper.testSlice(source, from, to);
      expect(offset).to.equal(from);
      expect(i).to.equal(0n);
      expect(len).to.equal(BigInt(ethers.getBytes(b).length));
    });

    it("slice reverts OutOfBounds when the requested range is invalid", async () => {
      const source = concat(encodeAssetBlock(asset), encodeAccountBlock(encodeUserAccount("0x12")));
      await expect(helper.testSlice(source, 10n, 9n))
        .to.be.revertedWithCustomError(helper, "OutOfBounds");
      await expect(helper.testSlice(source, 0n, BigInt(ethers.getBytes(source).length + 1)))
        .to.be.revertedWithCustomError(helper, "OutOfBounds");
    });

    it("raw returns the full cursor region as calldata", async () => {
      const source = concat(encodeAssetBlock(asset), encodeAccountBlock(encodeUserAccount("0x12")));
      expect(await helper.testRaw(source)).to.equal(source);
    });

    it("packed cursor raw returns only its unread calldata region", async () => {
      const a = encodeAssetBlock(asset);
      const b = encodeAccountBlock(encodeUserAccount("0x12"));
      expect(await helper.testCursorRaw(concat(a, b), ethers.getBytes(a).length)).to.equal(b);
    });

    it("raw returns a sliced cursor region as calldata", async () => {
      const a = encodeAssetBlock(asset);
      const b = encodeAccountBlock(encodeUserAccount("0x12"));
      const source = concat(a, b);
      const from = BigInt(ethers.getBytes(a).length);
      const to = BigInt(ethers.getBytes(source).length);
      expect(await helper.testRawSlice(source, from, to)).to.equal(b);
    });

    it("seek moves the cursor to the provided source position", async () => {
      const source = concat(encodeAssetBlock(asset), encodeAssetBlock(otherAsset));
      expect(await helper.testSeek(source, BigInt(ethers.getBytes(source).length))).to.equal(BigInt(ethers.getBytes(source).length));
    });

    it("seek reverts OutOfBounds when moving the cursor backwards", async () => {
      const source = concat(encodeAssetBlock(asset), encodeAssetBlock(otherAsset));
      const end = BigInt(ethers.getBytes(source).length - ethers.getBytes(encodeAssetBlock(otherAsset)).length);
      await expect(helper.testSeekBackward(source, end))
        .to.be.revertedWithCustomError(helper, "OutOfBounds");
    });

    it("expect succeeds when the cursor is exactly at the requested position", async () => {
      const source = concat(encodeAssetBlock(asset), encodeAssetBlock(otherAsset));
      const pos = BigInt(ethers.getBytes(source).length);
      expect(await helper.testExpectPosition(source, pos)).to.equal(pos);
    });

    it("expect reverts UnexpectedPosition when the cursor is not exactly at the requested position", async () => {
      const source = concat(encodeAssetBlock(asset), encodeAssetBlock(otherAsset));
      const pos = BigInt(ethers.getBytes(encodeAssetBlock(asset)).length);
      await expect(helper.testExpectPositionMismatch(source, pos))
        .to.be.revertedWithCustomError(helper, "UnexpectedPosition");
    });

    it("list consumes the list and returns a cursor scoped to its payload", async () => {
      const item1 = encodeAssetBlock(asset);
      const item2 = encodeAssetBlock(otherAsset);
      const list = encodeListBlock(item1, item2);
      const [itemsOffset, itemsI, itemsLen, inputI] = await helper.testList(list);
      expect(itemsOffset).to.equal(8n);
      expect(itemsI).to.equal(0n);
      expect(itemsLen).to.equal(BigInt(ethers.getBytes(item1).length + ethers.getBytes(item2).length));
      expect(inputI).to.equal(BigInt(ethers.getBytes(list).length));
    });

    it("treats an empty list block as a present list with no items", async () => {
      const list = encodeListBlock();
      const [itemsOffset, itemsI, itemsLen, inputI] = await helper.testList(list);
      expect([itemsOffset, itemsI, itemsLen, inputI]).to.deep.equal([8n, 0n, 0n, 8n]);
    });

    it("list accepts custom keyed list specifications", async () => {
      const key = localKey(77);
      const item1 = encodeAssetBlock(asset);
      const item2 = encodeAssetBlock(otherAsset);
      const payload = concat(item1, item2);
      const list = encodeBlock(key, payload);
      const spec = exactSpec(key, ethers.getBytes(payload).length);

      const [itemsOffset, itemsI, itemsLen, inputI] = await helper.testListSpec(list, spec);
      expect(itemsOffset).to.equal(8n);
      expect(itemsI).to.equal(0n);
      expect(itemsLen).to.equal(BigInt(ethers.getBytes(payload).length));
      expect(inputI).to.equal(BigInt(ethers.getBytes(list).length));
      expect(await blocksHelper.executionList(list, spec))
        .to.deep.equal([BigInt(ethers.getBytes(payload).length), true]);
    });

    it("custom local blocks carry merged payload fields without child headers", async () => {
      const custom = localKey(1);
      const payload = ethers.concat([
        asset,
        otherAsset,
        ethers.zeroPadValue(ethers.toBeHex(amount), 32),
        ethers.zeroPadValue(ethers.toBeHex(77n), 32),
      ]);
      const data = encodeBlock(custom, payload);

      expect(data.slice(0, 10)).to.equal(custom);
      expect(await helper.testPeek(data, 0n)).to.deep.equal([custom, 128n]);
      expect(ethers.getBytes(data).length).to.equal(136);
      expect(data).to.not.include(Keys.Amount.slice(2));
    });

    it("takeBlock returns a cursor over the full matching block and advances the source cursor", async () => {
      const custom = localKey(1);
      const payload = encodeAccountBlock(encodeUserAccount("0x12"));
      const data = encodeBlock(custom, payload);
      const [outOffset, outI, outLen, inputI] = await helper.testTakeBlock(data, custom);
      expect(outOffset).to.equal(0n);
      expect(outI).to.equal(0n);
      expect(outLen).to.equal(BigInt(ethers.getBytes(data).length));
      expect(inputI).to.equal(BigInt(ethers.getBytes(data).length));
    });

    it("takeBlock reverts when the current block key does not match", async () => {
      const custom = localKey(1);
      const source = encodeBalanceBlock(asset, amount);
      await expect(helper.testTakeBlock(source, custom))
        .to.be.revertedWithCustomError(helper, "InvalidBlock");
    });

    it("execution takeBlock returns the full block and preserves state", async () => {
      const custom = localKey(1);
      const input = encodeBlock(custom, encodeAccountBlock(encodeUserAccount("0x12")));
      const state = encodeBalanceBlock(asset, amount);

      expect(await blocksHelper.executionTakeBlock(encodeContextBlock(ethers.ZeroHash, state, input), custom, custom))
        .to.deep.equal([input, asset, amount, true]);
    });

    it("execution takeBlock reverts when the current block key does not match", async () => {
      const custom = localKey(1);
      const other = localKey(2);
      const input = encodeBlock(custom, "0x1234");
      const state = encodeBalanceBlock(asset, amount);

      await expect(blocksHelper.executionTakeBlock(encodeContextBlock(ethers.ZeroHash, state, input), custom, other))
        .to.be.revertedWithCustomError(blocksHelper, "InvalidBlock");
    });

    it("decoder and execution raw return unread sources from the current position", async () => {
      const state = encodeBalanceBlock(asset, amount);
      const input = encodeAmountBlock(asset, 7n);
      const first = ethers.zeroPadValue("0x41", 32);
      const second = ethers.zeroPadValue("0x42", 32);

      expect(await blocksHelper.executionRaw(encodeContextBlock(ethers.ZeroHash, state, input)))
        .to.deep.equal([state, "0x", input]);
      expect(await blocksHelper.executionRawEmptyState(input)).to.equal("0x");
      expect(await helper.testDecoderRaw(concat(first, second), 32n)).to.equal(second);
    });

    it("takeRawState returns the unread state source and consumes it", async () => {
      const state = encodeBalanceBlock(asset, amount);
      expect(await blocksHelper.executionTakeRawState(encodeContextBlock(ethers.ZeroHash, state, "0x"))).to.deep.equal([state, true]);
    });

    it("takeRawInput returns the unread input source and consumes it", async () => {
      const input = encodeAmountBlock(asset, amount);
      expect(await blocksHelper.executionTakeRawInput(input)).to.deep.equal([input, true]);
    });

    it("raw forwarding preserves independent EMPTY lane restrictions", async () => {
      const state = encodeBalanceBlock(asset, amount);
      const input = encodeAmountBlock(asset, amount);
      const stateSpec = exactSpec(Keys.Balance, 64);
      const inputSpec = exactSpec(Keys.Amount, 64);
      expect(await blocksHelper.executionForwardRaw(encodeContextBlock(ethers.ZeroHash, state, input), stateSpec, inputSpec)).to.equal("0x");
      expect(await blocksHelper.executionForwardRaw(encodeContextBlock(ethers.ZeroHash, "0x", input), 0, inputSpec)).to.equal("0x");
      expect(await blocksHelper.executionForwardRaw(encodeContextBlock(ethers.ZeroHash, state, "0x"), stateSpec, 0)).to.equal("0x");
      await expect(blocksHelper.executionForwardRaw(encodeContextBlock(ethers.ZeroHash, state, input), 0, inputSpec))
        .to.be.revertedWithCustomError(blocksHelper, "UnconsumedData");
      await expect(blocksHelper.executionForwardRaw(encodeContextBlock(ethers.ZeroHash, state, input), stateSpec, 0))
        .to.be.revertedWithCustomError(blocksHelper, "UnconsumedData");
    });

    it("finish rejects unread execution data", async () => {
      const input = encodeAmountBlock(asset, amount);
      await expect(blocksHelper.executionFinishUnread(input))
        .to.be.revertedWithCustomError(blocksHelper, "UnconsumedData");

      const state = encodeBalanceBlock(asset, amount);
      await expect(blocksHelper.executionFinishUnreadState(encodeContextBlock(ethers.ZeroHash, state, "0x")))
        .to.be.revertedWithCustomError(blocksHelper, "UnconsumedData");
    });

    it("unpackStep consumes the block and returns the trailing input", async () => {
      const req = encodeAmountBlock(asset, amount);
      const step = encodeStepBlock(7n, 55n, req);
      const [cmd, value, outReq, i] = await helper.testUnpackStep(step);
      expect(cmd).to.equal(7n);
      expect(value).to.equal(55n);
      expect(outReq).to.equal(req);
      expect(i).to.equal(BigInt(ethers.getBytes(step).length));
    });

    it("packs STEP value into one full word", async () => {
      const value = (1n << 256n) - 1n;
      const step = encodeStepBlock(7n, value, "0x");

      expect(ethers.getBytes(step).length).to.equal(80);
      expect(await helper.testUnpackStep(step)).to.deep.equal([7n, value, "0x", 80n]);
    });

    it("unpackContext consumes account, state, and input bytes", async () => {
      const account = encodeUserAccount("0x12");
      const state = encodeBalanceBlock(asset, amount);
      const input = encodeAmountBlock(asset, 7n);
      const context = encodeContextBlock(account, state, input);
      const [outAccount, outState, outInput, i] = await helper.testUnpackContext(context);
      expect(outAccount).to.equal(account);
      expect(outState).to.equal(state);
      expect(outInput).to.equal(input);
      expect(i).to.equal(BigInt(ethers.getBytes(context).length));
    });

    it("unpackRecover consumes handler, resources, key, and witness bytes", async () => {
      const handler = 42n;
      const key = ethers.zeroPadValue("0x1234", 32);
      const account = encodeUserAccount("0x12");
      const state = encodeBalanceBlock(asset, amount);
      const input = encodeAmountBlock(asset, 7n);
      const witness = encodeContextBlock(account, state, input);
      const resources = 55n;
      const recovery = encodeRecoverBlock(handler, resources, key, witness);
      const [outHandler, outResources, outKey, outWitness, i] = await helper.testUnpackRecover(recovery);
      expect(outHandler).to.equal(handler);
      expect(outResources).to.equal(resources);
      expect(outKey).to.equal(key);
      expect(outWitness).to.equal(witness);
      expect(i).to.equal(BigInt(ethers.getBytes(recovery).length));
    });

    it("unpackRelay consumes implementation-specific input and remaining steps", async () => {
      const portal: bigint = await utils.testLocalChainId();
      const input = encodeStepBlock(0n, 0n, encodeAmountBlock(asset, 7n));
      const relay = encodeRelayBlock(ethers.concat([pad32(portal), pad32(55n)]), input);
      const [outPortal, resources, outInput, i] = await helper.testUnpackRelay(relay);
      expect(outPortal).to.equal(portal);
      expect(resources).to.equal(55n);
      expect(outInput).to.equal(input);
      expect(i).to.equal(BigInt(ethers.getBytes(relay).length));
    });

    it("unpackRelay keeps arbitrary command input separate from continuation steps", async () => {
      const commandInput = encodeAmountBlock(asset, 7n);
      const steps = encodeStepBlock(0n, 0n, "0x1234");
      const relay = encodeRelayBlock(commandInput, steps);
      const [outInput, outSteps, i] = await helper.testUnpackRelayStreams(relay);
      expect(outInput).to.equal(commandInput);
      expect(outSteps).to.equal(steps);
      expect(i).to.equal(BigInt(ethers.getBytes(relay).length));
    });

    it("unpackDispatch consumes portal, resources, and payload bytes", async () => {
      const portal: bigint = await utils.testLocalChainId();
      const payload = ethers.hexlify(ethers.toUtf8Bytes("ready-to-send"));
      const dispatch = encodeDispatchBlock(portal, 89n, payload);
      const [outPortal, resources, outPayload, i] = await helper.testUnpackDispatch(dispatch);
      expect(outPortal).to.equal(portal);
      expect(resources).to.equal(89n);
      expect(outPayload).to.equal(payload);
      expect(i).to.equal(BigInt(ethers.getBytes(dispatch).length));
    });

    it("unpackString consumes a STRING block and returns the decoded string", async () => {
      const label = "label schema";
      const source = encodeStringBlock(label);
      const [out, i] = await stringHelper.testUnpackString(source);
      expect(out).to.equal(label);
      expect(i).to.equal(BigInt(ethers.getBytes(source).length));
    });

    it("unpackLabel consumes a LABEL block and returns its fields", async () => {
      const namespace = ethers.encodeBytes32String("peer");
      const name = "portDispatchPayable";
      const source = encodeLabelBlock(namespace, name);
      const [outNamespace, outName, i] = await stringHelper.testUnpackLabel(source);
      expect(outNamespace).to.equal(namespace);
      expect(outName).to.equal(name);
      expect(i).to.equal(BigInt(ethers.getBytes(source).length));
    });

    for (const body of [
      "", "opaque:", "bytes32 asset",
      "amount: { bytes32 asset, uint amount }",
      "assets: many #asset as assets",
      "portfolio: many #asset as holdings",
      "relay.input: uint portal, uint resources",
      "longSchemaNameBeyondThirtyTwoCharacters: uint value",
    ]) {
      it(`round-trips the complete schema string ${JSON.stringify(body)}`, async () => {
        const spec = exactSpec(Keys.Amount, 64);
        const source = encodeSchemaBlock(spec, body);
        expect(await helper.testToSchemaBlock(spec, body)).to.equal(source);
        const [outSpec, outBody, i] = await stringHelper.testUnpackSchema(source);
        expect(outSpec).to.equal(spec);
        expect(outBody).to.equal(body);
        expect(i).to.equal(BigInt(48 + ethers.toUtf8Bytes(body).length));
      });
    }

    it("rejects schema truncation, invalid child headers, and the former trailing name word", async () => {
      const spec = exactSpec(Keys.Amount, 64);
      const source = encodeSchemaBlock(spec, "assets: many #asset as assets");
      for (let length = 0; length < ethers.dataLength(source); length++) {
        await expect(stringHelper.testUnpackSchema(ethers.dataSlice(source, 0, length)))
          .to.be.revertedWithCustomError(stringHelper, length < 48 ? "InvalidBlock" : "OutOfBounds");
      }
      for (const payload of [
        pad32(spec),
        ethers.concat([pad32(spec), encodeBytesBlock("0x")]),
        ethers.concat([pad32(spec), encodeStringBlock("uint value"), ethers.ZeroHash]),
      ]) {
        await expect(stringHelper.testUnpackSchema(encodeBlock(Keys.Schema, payload)))
          .to.be.revertedWithCustomError(stringHelper, "InvalidBlock");
      }
    });

    it("unpackAccount returns the account word", async () => {
      const account = encodeUserAccount("0x12");
      const source = encodeAccountBlock(account);
      expect(await helper.testUnpackAccount(source)).to.equal(account);
    });

    it("expectErc20Amount returns the token and amount from a local ERC20 amount block", async () => {
      const token = "0x00000000000000000000000000000000000000a0";
      const assetId = await utils.testToErc20Asset(token);
      const source = encodeAmountBlock(assetId, 66n);

      expect(await erc20Helper.testExpectErc20Amount(source, 0n)).to.deep.equal([token, 66n]);
    });

    it("requireErc20Amount returns the token and amount and advances by one amount block", async () => {
      const token = "0x00000000000000000000000000000000000000a0";
      const assetId = await utils.testToErc20Asset(token);
      const source = encodeAmountBlock(assetId, 66n);

      expect(await erc20Helper.testRequireErc20Amount(source)).to.deep.equal([token, 66n, 72n]);
    });

    it("expectErc20Balance returns the token and amount from a local ERC20 balance block", async () => {
      const token = "0x00000000000000000000000000000000000000a0";
      const assetId = await utils.testToErc20Asset(token);
      const source = encodeBalanceBlock(assetId, 67n);

      expect(await erc20Helper.testExpectErc20Balance(source, 0n)).to.deep.equal([token, 67n]);
    });

    it("requireErc20Balance returns the token and amount and advances by one balance block", async () => {
      const token = "0x00000000000000000000000000000000000000a0";
      const assetId = await utils.testToErc20Asset(token);
      const source = encodeBalanceBlock(assetId, 67n);

      expect(await erc20Helper.testRequireErc20Balance(source)).to.deep.equal([token, 67n, 72n]);
    });

    it("expectErc20Custody returns the token and amount from a local ERC20 custody block", async () => {
      const token = "0x00000000000000000000000000000000000000a0";
      const assetId = await utils.testToErc20Asset(token);
      const source = encodeCustodyBlock(123n, assetId, 68n);

      expect(await erc20Helper.testExpectErc20Custody(source, 0n, 123n)).to.deep.equal([token, 68n]);
    });

    it("requireErc20Custody returns the token, amount, and advances by one custody block", async () => {
      const token = "0x00000000000000000000000000000000000000a0";
      const assetId = await utils.testToErc20Asset(token);
      const source = encodeCustodyBlock(123n, assetId, 68n);

      expect(await erc20Helper.testRequireErc20Custody(source, 123n)).to.deep.equal([token, 68n, 104n]);
    });

    it("expectErc20Custody reverts UnexpectedValue when the host does not match", async () => {
      const token = "0x00000000000000000000000000000000000000a0";
      const assetId = await utils.testToErc20Asset(token);
      const source = encodeCustodyBlock(123n, assetId, 68n);

      await expect(erc20Helper.testExpectErc20Custody(source, 0n, 321n))
        .to.be.revertedWithCustomError(erc20Helper, "UnexpectedValue");
    });

    it("expectErc20Amount reverts InvalidAsset when the asset is not a local ERC20", async () => {
      const assetId = await utils.testToChain();
      const source = encodeAmountBlock(assetId, 77n);

      await expect(erc20Helper.testExpectErc20Amount(source, 0n))
        .to.be.revertedWithCustomError(erc20Helper, "InvalidAsset");
    });

    it("opens state and input independently of their block counts", async () => {
      const state = concat(
        encodeBalanceBlock(asset, 1n),
        encodeBalanceBlock(asset, 2n),
      );
      const input = encodeAmountBlock(asset, 3n);

      expect(await operation.testOpenSources(encodeContextBlock(ethers.ZeroHash, state, input))).to.equal(true);
    });

    it("does not pre-scan or reconcile state and input counts", async () => {
      const state = concat(
        encodeBalanceBlock(asset, 1n),
        encodeBalanceBlock(asset, 2n),
        encodeBalanceBlock(asset, 3n),
      );
      const input = encodeAmountBlock(asset, 4n);

      expect(await operation.testOpenSources(encodeContextBlock(ethers.ZeroHash, state, input))).to.equal(true);
    });
  });

});
