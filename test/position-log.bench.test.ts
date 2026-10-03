import { expect } from "chai";
import { ethers } from "ethers";
import { writeFile } from "node:fs/promises";
import { deploy } from "./helpers/setup.js";
import { concat, encodeCodesBlock, encodePositionBlock } from "./helpers/blocks.js";

const variants = ["Separate", "Reuse", "Fused", "FusedStores", "RawBlock", "Bytes", "AnonymousIndexed", "Anonymous", "Compact", "FusedFast", "AnonymousFast", "Adaptive", "Compact64", "Batch", "FusedInline", "AnonymousInline", "Compact64Inline", "AdaptiveInline", "BatchCompact"];
const abi = ethers.AbiCoder.defaultAbiCoder();
const account = ethers.toBeHex(0xabcdefn << 224n, 32);
const asset = ethers.toBeHex(0x123456n << 224n, 32);
const liability = ethers.toBeHex(0x789abcn << 224n, 32);
const counterparty = ethers.toBeHex(0xdef012n << 224n, 32);
const cases = [
  { name: "typical", amount: 10n ** 18n, debt: 2n * 10n ** 18n, codes: 4n | (0x20000006n << 32n) | (0xa0000001n << 64n) },
  { name: "full-width", amount: ethers.MaxUint256, debt: ethers.MaxUint256 - 1n, codes: ethers.MaxUint256 - 2n },
  { name: "zero", amount: 0n, debt: 0n, codes: 0n },
  { name: "128-bit", amount: 1n << 100n, debt: (1n << 128n) - 1n, codes: 1n << 127n },
];

function checkBatch(variant: string, log: any, positions: (string | bigint)[][], codes: bigint) {
  expect(log.topics).deep.eq([]);
  if (variant === "Batch") {
    expect(log.data).eq(concat(account, ethers.toBeHex(codes, 32), ...positions.map(p =>
      abi.encode(["bytes32", "uint256", "bytes32", "uint256", "bytes32"], p))));
    return;
  }
  const small = codes < (1n << 96n) && positions.every(p => (p[1] as bigint) < (1n << 64n) && (p[3] as bigint) < (1n << 64n));
  const zero = codes === 0n && positions.every(p => p[1] === 0n && p[3] === 0n);
  const kind = zero ? 2 : small ? 1 : 0;
  const records = positions.map(p => kind === 0
    ? abi.encode(["bytes32", "uint256", "bytes32", "uint256", "bytes32"], p)
    : concat(p[0] as string, p[2] as string, p[4] as string,
      kind === 1 ? concat(ethers.toBeHex(p[1], 8), ethers.toBeHex(p[3], 8)) : "0x"));
  expect(log.data).eq(concat(ethers.toBeHex(kind, 1), account,
    kind === 0 ? ethers.toBeHex(codes, 32) : kind === 1 ? ethers.toBeHex(codes, 12) : "0x", ...records));
}

function checkLog(variant: string, log: any, position: readonly unknown[], codes: bigint, block: string) {
  variant = variant.replace(/Inline$/, "");
  const fields = abi.encode(["bytes32", "uint256", "bytes32", "uint256", "bytes32", "uint256"], [...position, codes]);
  const topic = ethers.id("Positioned(bytes32,bytes32,uint256,bytes32,uint256,bytes32,uint256)");
  if (["Separate", "Reuse", "Fused", "FusedStores", "FusedFast"].includes(variant)) {
    expect(log.topics).deep.eq([topic, account]);
    expect(log.data).eq(fields);
  } else if (variant === "RawBlock") {
    expect(log.topics).deep.eq([ethers.id("rootzero.position.block.v1"), account]);
    expect(log.data).eq(concat(ethers.toBeHex(codes, 32), block));
  } else if (variant === "Bytes") {
    expect(log.topics).deep.eq([ethers.id("PositionBytes(bytes32,uint256,bytes)"), account]);
    expect(Array.from(abi.decode(["uint256", "bytes"], log.data))).deep.eq([codes, block]);
    expect(ethers.dataLength(log.data)).eq(288);
  } else if (variant === "AnonymousIndexed") {
    expect(log.topics).deep.eq([account]);
    expect(log.data).eq(fields);
  } else if (variant === "Anonymous" || variant === "AnonymousFast") {
    expect(log.topics).deep.eq([]);
    expect(log.data).eq(concat(account, fields));
  } else if (variant === "Adaptive" || variant === "Compact64") {
    expect(log.topics).deep.eq([]);
    const data = ethers.getBytes(log.data);
    if (data.length === 224) {
      expect(log.data).eq(concat(account, fields));
    } else {
      expect(ethers.hexlify(data.slice(0, 128))).eq(concat(account, asset, liability, counterparty));
      const widths = data.length === 128 ? [0, 0, 0] : data.length === 156 ? [8, 8, 12] : [16, 16, 16];
      let cursor = 128;
      const numbers = widths.map(width => {
        const value = width ? BigInt(ethers.hexlify(data.slice(cursor, cursor + width))) : 0n;
        cursor += width;
        return value;
      });
      expect(cursor).eq(data.length);
      expect(numbers).deep.eq([position[1], position[3], codes]);
    }
  } else {
    expect(log.topics).deep.eq([]);
    const data = ethers.getBytes(log.data);
    const widths = Array.from(data.slice(0, 3));
    expect(ethers.hexlify(data.slice(3, 131))).eq(concat(account, asset, liability, counterparty));
    let cursor = 131;
    const numbers = widths.map(width => {
      expect(width).at.most(32);
      const bytes = data.slice(cursor, cursor + width);
      cursor += width;
      if (width) expect(bytes[0]).not.eq(0);
      return width ? BigInt(ethers.hexlify(bytes)) : 0n;
    });
    expect(numbers).deep.eq([position[1], position[3], codes]);
    expect(cursor).eq(data.length);
  }
}

describe("Position log and output gas", function () {
  this.timeout(180_000);
  it("compares equivalent information and verifies logs plus output across growth and scratch reuse", async () => {
    const rows: object[] = [];
    for (const variant of variants) {
      const helper = await deploy("PositionLog" + variant);
      // Different adjacent positions catch wrong offsets, stale pointers, and
      // accidental mutation of previous output. Include compression boundaries.
      for (const codes of [0n, (1n << 96n) - 1n, 1n << 96n, 1n << 128n]) {
        const positions = [
          [asset, (1n << 64n) - 1n, liability, 0n, counterparty],
          [asset, 1n << 64n, liability, (1n << 128n) - 1n, counterparty],
          [asset, 1n << 128n, liability, ethers.MaxUint256, counterparty],
        ];
        const blocks = positions.map(p => encodePositionBlock(p[0] as string, p[1] as bigint,
          p[2] as string, p[3] as bigint, p[4] as string));
        expect(await helper.verifyMany.staticCall(positions, account, codes, 40))
          .eq(concat(encodeCodesBlock(0x1234n), ...blocks, encodeCodesBlock(0x5678n)));
        const receipt = await (await helper.verifyMany(positions, account, codes, 40)).wait();
        if (variant.startsWith("Batch")) {
          expect(receipt.logs.length).eq(1);
          checkBatch(variant, receipt.logs[0], positions, codes);
        } else {
          expect(receipt.logs.length).eq(positions.length);
          receipt.logs.forEach((log: any, i: number) => checkLog(variant, log, positions[i], codes, blocks[i]));
        }
      }
      for (const sample of cases) {
        const position = [asset, sample.amount, liability, sample.debt, counterparty];
        const block = encodePositionBlock(asset, sample.amount, liability, sample.debt, counterparty);
        for (const [scenario, capacity, count, sentinels] of [
          ["reserved", 168, 1, false],
          ["growth", 0, 1, false],
          ["batch-growth", 40, 4, true],
          ["batch-reserved", 752, 4, true],
        ] as const) {
          const args = [position, account, sample.codes, capacity, count, sentinels] as const;
          const result = await helper.measure.staticCall(...args);
          const expected = concat(
            sentinels ? encodeCodesBlock(0x1234n) : "0x", ...Array(count).fill(block),
            sentinels ? encodeCodesBlock(0x5678n) : "0x",
          );
          expect(result.output, `${variant}/${scenario}`).eq(expected);
          const receipt = await (await helper.measure(...args)).wait();
          expect(receipt.logs.length).eq(variant.startsWith("Batch") ? 1 : count);
          if (variant.startsWith("Batch")) {
            checkBatch(variant, receipt.logs[0], Array(count).fill(position), sample.codes);
          } else {
            for (const log of receipt.logs) checkLog(variant, log, position, sample.codes, block);
          }
          rows.push({ variant, sample: sample.name, scenario, count, helperGas: Number(result.used),
            gasPerPosition: Number(result.used) / count, transactionGas: Number(receipt.gasUsed),
            logBytes: ethers.dataLength(receipt.logs[0].data), topics: receipt.logs[0].topics.length });
        }
      }
    }
    console.table(rows.filter((row: any) => row.scenario === "reserved"));
    await writeFile("docs/benchmarks/POSITION_LOG.json", JSON.stringify({
      compiler: "solc 0.8.35, viaIR, optimizer runs 200, Cancun",
      scope: "Opened Execution and memory Position; times combined log/output loop, excluding initial writer allocation, sentinels, finish, and ABI return encoding. Transaction gas is included separately. All variants preserve account, five position fields, and codes.",
      rows,
    }, null, 2) + "\n");
  });
});
