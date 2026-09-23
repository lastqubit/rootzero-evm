import { expect } from "chai";
import { deploy, getProvider, getSigner } from "./helpers/setup.js";
import "./helpers/matchers.js";
import {
  concat,
  encodeAccountAssetBlock,
  encodeAccountAmountBlock,
  encodeUserAccount,
} from "./helpers/blocks.js";

describe("BalancesQuery", () => {
  it("returns empty output for empty input and rejects a truncated trailing item", async () => {
    const query = await deploy("TestBalancesQuery");
    expect(await query.getBalance.staticCall("0x")).to.equal("0x");
    const account = encodeUserAccount(await (await getSigner()).getAddress());
    const input = concat(encodeAccountAssetBlock(account, await query.tokenAsset()), "0x01");
    await expect(query.getBalance.staticCall(input)).to.be.revertedWithCustomError(query, "OutOfBounds");
  });

  it("queries the host account through the same account balance endpoint", async () => {
    const query = await deploy("TestBalancesQuery");
    const tokenAsset = await query.tokenAsset();
    const chainAsset = await query.chainAssetId();
    const queryAddress = await query.getAddress();

    await query.mint(queryAddress, 789n);
    await (await getSigner(0)).sendTransaction({ to: queryAddress, value: 37n });

    const utils = await deploy("TestUtils");
    const account = await utils.testToHostAccount(queryAddress);
    const input = concat(encodeAccountAssetBlock(account, tokenAsset), encodeAccountAssetBlock(account, chainAsset));
    const result: string = await query.getBalance.staticCall(input);

    expect(result).to.equal(concat(
      encodeAccountAmountBlock(account, tokenAsset, 789n),
      encodeAccountAmountBlock(account, chainAsset, 37n),
    ));
  });

  it("returns an entry block for one ERC-20 position query", async () => {
    const query = await deploy("TestBalancesQuery");
    const account = await getSigner(1);
    const accountId = encodeUserAccount(await account.getAddress());
    const tokenAsset = await query.tokenAsset();

    await query.mint(await account.getAddress(), 123n);

    const input = encodeAccountAssetBlock(accountId, tokenAsset);
    const result: string = await query.getBalance.staticCall(input);

    expect(result).to.equal(encodeAccountAmountBlock(accountId, tokenAsset, 123n));
  });

  it("maps multiple position blocks into matching entry blocks in order", async () => {
    const query = await deploy("TestBalancesQuery");
    const provider = await getProvider();
    const account = await getSigner(1);
    const accountAddr = await account.getAddress();
    const accountId = encodeUserAccount(accountAddr);
    const tokenAsset = await query.tokenAsset();
    const chainAsset = await query.chainAssetId();

    await query.mint(accountAddr, 456n);
    const nativeBalance = await provider.getBalance(accountAddr);

    const input = concat(
      encodeAccountAssetBlock(accountId, tokenAsset),
      encodeAccountAssetBlock(accountId, chainAsset),
    );

    const result: string = await query.getBalance.staticCall(input);

    expect(result).to.equal(concat(
      encodeAccountAmountBlock(accountId, tokenAsset, 456n),
      encodeAccountAmountBlock(accountId, chainAsset, nativeBalance),
    ));
  });
});
