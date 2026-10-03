import { expect } from "chai";
import { ethers } from "ethers";
import { deploy } from "./helpers/setup.js";
import { Keys, encodeBlock } from "./helpers/blocks.js";
import "./helpers/matchers.js";

describe("Blocks migration behavior", () => {
  it("takes balance streams with metadata-free execution cursors", async () => {
    const helper = await deploy("TestTakeBalances");
    const good = encodeBlock(Keys.Balance, ethers.toBeHex(1, 64));
    for (const source of ["0x", good, ethers.concat([good, good])]) {
      const result = await helper.takeBalanceState(source, 0, ethers.dataLength(source));
      expect(result.selected).eq(result.beforeCur & ((1n << 64n) - 1n));
      expect(result.afterCur >> 32n).eq(result.beforeCur >> 32n);
      expect(result.afterCur & 0xffffffffn).eq((result.beforeCur >> 32n) & 0xffffffffn);
      expect(result.input).eq(123n);
    }
    // Stream validation still rejects reversed bounds. Calldata provenance is
    // established by execution opening, not rechecked by takeBalances.
    await expect(helper.takeBalanceState(good, 72, 0))
      .revertedWithCustomError(helper, "OutOfBounds");
  });

  it("retains header rejection but identifies changed truncation errors", async () => {
    const old = await deploy("BlocksMigrationBaseline");
    const next = await deploy("BlocksMigrationCandidate");
    for (const [name, memory, key, words] of [
      ["CreditAccount", true, Keys.Balance, 2], ["Cashout", true, Keys.Balance, 2],
      ["Settle", true, Keys.Position, 5], ["DebitAccount", false, Keys.AssetAmount, 2],
      ["Bootstrap", false, Keys.Bootstrap, 3], ["Authorize", false, Keys.Node, 1],
    ] as const) {
      const method = "measure" + name;
      const good = encodeBlock(key, ethers.concat(Array(words).fill(ethers.toBeHex(1, 32))));
      const badHeader = ethers.concat(["0x12345678", ethers.dataSlice(good, 4)]);
      for (const helper of [old, next]) {
        await expect(helper[method].staticCall(memory ? badHeader : "0x", memory ? "0x" : badHeader, 100))
          .revertedWithCustomError(helper, "InvalidBlock");
      }
      const partial = ethers.concat([good, ethers.dataSlice(good, 0, ethers.dataLength(good) - 1)]);
      await expect(old[method].staticCall(memory ? partial : "0x", memory ? "0x" : partial, 100))
        .revertedWithCustomError(old, "InvalidBlock");
      await expect(next[method].staticCall(memory ? partial : "0x", memory ? "0x" : partial, 100))
        .revertedWithCustomError(next, "OutOfBounds");
      expect(await next.checksum()).eq(0n);
    }
  });

  it("preserves runCount stopping behavior for incomplete or mismatched blocks", async () => {
    const old = await deploy("BlocksEncodingMigrationBaseline");
    const next = await deploy("BlocksEncodingMigrationCandidate");
    const block = encodeBlock(Keys.Balance, ethers.toBeHex(1, 64));
    for (const suffix of ["0x", "0xff", ethers.dataSlice(block, 0, 7), ethers.dataSlice(block, 0, 71),
      encodeBlock(Keys.Node, ethers.toBeHex(2, 32))]) {
      const input = ethers.concat([block, suffix]);
      expect((await next.count(input, Keys.Balance))[1]).eq((await old.count(input, Keys.Balance))[1]);
    }
  });

  it("preserves relay balance validation and consumption without a calldata detour", async () => {
    const old = await deploy("BlocksEncodingMigrationBaseline");
    const next = await deploy("BlocksEncodingMigrationCandidate");
    const good = encodeBlock(Keys.Balance, ethers.concat([ethers.toBeHex(1, 32), ethers.toBeHex(7, 32)]));
    const wrong = ethers.concat([Keys.Node, ethers.dataSlice(good, 4)]);
    for (const [state, error] of [
      [ethers.dataSlice(good, 0, 71), "OutOfBounds"],
      [wrong, "InvalidBlock"],
      [ethers.concat([wrong, "0xff"]), "InvalidBlock"],
      [ethers.concat([good, "0xff"]), "OutOfBounds"],
    ]) {
      for (const helper of [old, next]) {
        await expect(helper.relayBalances(ethers.toBeHex(9, 32), state, "0x1234"))
          .revertedWithCustomError(helper, error);
      }
    }
  });
});
