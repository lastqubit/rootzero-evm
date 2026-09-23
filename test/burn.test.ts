import { expect } from "chai";
import { ethers } from "ethers";
import { commandId, deploy, getSigner, hostId } from "./helpers/setup.js";
import { concat, encodeActionBlock, encodeAmountBlock, encodeBalanceBlock, encodeContextBlock } from "./helpers/blocks.js";
import "./helpers/matchers.js";

describe("Burn", () => {
  let host: Awaited<ReturnType<typeof deploy>>;
  let userAccount: string;
  const burnMethod = "burn(bytes)";

  before(async () => {
    const signer = await getSigner(0);
    const commander = await signer.getAddress();
    host = await deploy("TestBurnHost", await hostId(commander));

    const USER_PREFIX = 0x03010300n;
    userAccount = ethers.zeroPadValue(
      ethers.toBeHex((USER_PREFIX << 224n) | BigInt(commander)),
      32
    );
  });

  function ctx(overrides: Partial<{ account: string; state: string; input: string }> = {}) {
    return [
      encodeContextBlock(
        overrides.account ?? userAccount,
        overrides.state ?? "0x",
        overrides.input ?? "0x",
      ),
    ] as const;
  }

  async function callAs(signerIndex: number, ...args: unknown[]) {
    const signer = await getSigner(signerIndex);
    const callArgs = Array.isArray(args[0]) ? [...args[0], ...args.slice(1)] : args;
    return (host.connect(signer) as any)[burnMethod](...callArgs);
  }

  it("annotates burn with its semantic action", async () => {
    const deployment = host.deploymentTransaction();
    expect(deployment).to.not.equal(null);

    await expect(deployment!).to.emit(host, "Annotation")
      .withArgs(await commandId(burnMethod, host), encodeActionBlock(49n));
  });

  // â”€â”€ Happy path â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  it("emits BurnCalled for a single BALANCE block in state", async () => {
    const asset = ethers.zeroPadValue("0xa1", 32);
    const state = encodeBalanceBlock(asset, 100n);
    const tx = await callAs(0, ctx({ state }));
    await expect(tx).to.emit(host, "BurnCalled").withArgs(userAccount, asset, 100n);
  });

  it("emits BurnCalled for each BALANCE block when multiple are present", async () => {
    const asset1 = ethers.zeroPadValue("0xb1", 32);
    const asset2 = ethers.zeroPadValue("0xb2", 32);
    const state  = concat(
      encodeBalanceBlock(asset1, 10n),
      encodeBalanceBlock(asset2, 20n)
    );
    const tx = await callAs(0, ctx({ state }));
    await expect(tx).to.emit(host, "BurnCalled").withArgs(userAccount, asset1, 10n);
    await expect(tx).to.emit(host, "BurnCalled").withArgs(userAccount, asset2, 20n);
  });

  it("returns empty bytes after processing BALANCE blocks", async () => {
    const state = encodeBalanceBlock(ethers.zeroPadValue("0xc1", 32), 50n);
    const [result, transactions] = await (host as any)[burnMethod].staticCall(...ctx({ state }));
    expect(result).to.equal("0x");
    expect(transactions).to.equal(0n);
  });

  it("rejects a non-BALANCE block after a valid balance", async () => {
    const asset = ethers.zeroPadValue("0xd1", 32);
    const state = concat(encodeBalanceBlock(asset, 5n), encodeAmountBlock(asset, 5n));
    await expect(callAs(0, ctx({ state }))).to.be.revertedWithCustomError(host, "InvalidBlock");
  });

  // â”€â”€ Target / access guards â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  it("reverts AccessDenied for an untrusted caller", async () => {
    const state = encodeBalanceBlock(ethers.zeroPadValue("0xf2", 32), 1n);
    await expect(callAs(1, ctx({ state })))
      .to.be.revertedWithCustomError(host, "AccessDenied");
  });

  // â”€â”€ Error cases â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  it("accepts an empty state batch", async () => {
    expect(await (host as any)[burnMethod].staticCall(...ctx())).to.deep.equal(["0x", 0n]);
  });
});
