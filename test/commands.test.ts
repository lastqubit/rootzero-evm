import { expect } from "chai";
import { ethers } from "ethers";
import { commandId, deploy, getSigner, hostId } from "./helpers/setup.js";
import "./helpers/matchers.js";
import {
  Keys,
  endpointDescriptor,
  exactSpec,
  encodeBootstrapBlock,
  encodeAssetBlock,
  encodeAmountBlock,
  MaxUint128, encodeLimitsBlock,  encodeHostAccount,
  encodeBalanceBlock, encodeLiabilityPosition, encodePositionBlock, encodeAllocationBlock, encodeCustodyBlock,
  encodeAccountBlock, encodeNodeBlock, encodeStepBlock, encodeUserAccount,
  encodeActionBlock, encodeContextBlock, encodeRecoverBlock, encodeRelayBlock, encodeRelayInputBlock,
  encodeTxBlock, encodeLabelBlock, encodeSchemaBlock, localKey,
  concat
} from "./helpers/blocks.js";

describe("Commands", () => {
  const HandoffFunded = 0x81n;
  const RelayInputSpec = exactSpec(localKey(3), 64);
  let host: Awaited<ReturnType<typeof deploy>>;
  let remote: Awaited<ReturnType<typeof deploy>>;
  let utils: Awaited<ReturnType<typeof deploy>>;
  let commander: string;
  let userAccount: string;
  let adminAccount: string;

  before(async () => {
    const signer = await getSigner(0);
    commander = await signer.getAddress();
    host = await deploy("TestHost", await hostId(commander));
    remote = await deploy("TestRemoteCommand");
    utils = await deploy("TestUtils");
    adminAccount = await host.getAdminAccount();

    const trustedCommands = await Promise.all([
      ...["noop", "first", "second", "credit"].map((method) => remoteCmd(method)),
      ...[
        "bootstrap",
        "cashout",
        "debitAccount",
        "creditAccount",
        "settle",
        "deposit",
        "realize",
        "relayPayable",
        "relayBalancePayable",
      ].map((method) => cmd(method)),
    ]);
    await host.authorize(
      encodeContextBlock(
        adminAccount,
        "0x",
        concat(...trustedCommands.map((command) => encodeNodeBlock(command))),
      ),
    );

    // Build a user account (unspecified prefix + address)
    const addrBig = BigInt(commander);
    // USER_PREFIX = [Evm][Account][User][flags=0] = 0x03010300
    const USER_PREFIX = 0x03010300n;
    userAccount = ethers.zeroPadValue(
      ethers.toBeHex((USER_PREFIX << 224n) | addrBig), 32
    );
    await host.setAcceptedSettleCounterparty(userAccount);
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

  function callAs(signerIndex: number, method: string, ...args: unknown[]) {
    const promise = getSigner(signerIndex).then((signer) => {
      const callArgs = Array.isArray(args[0]) ? [...args[0], ...args.slice(1)] : args;
      const txPromise = (host.connect(signer) as any)[method](...callArgs);
      Promise.resolve(txPromise).catch(() => {});
      return txPromise;
    });
    Promise.resolve(promise).catch(() => {});
    return promise;
  }

  async function withDepositFee(fee: bigint, test: () => Promise<void>) {
    await host.setDepositFee(fee);
    try {
      await test();
    } finally {
      await host.setDepositFee(0n);
    }
  }

  async function withRealizeFee(fee: bigint, test: () => Promise<void>) {
    await host.setRealizeFee(fee);
    try {
      await test();
    } finally {
      await host.setRealizeFee(0n);
    }
  }

  async function withRealizeDebtFee(fee: bigint, test: () => Promise<void>) {
    await host.setRealizeDebtFee(fee);
    try {
      await test();
    } finally {
      await host.setRealizeDebtFee(0n);
    }
  }

  async function cmd(method: string) {
    return commandId(`${method}(bytes)`, host, commandFlags(method));
  }

  function commandFlags(method: string): bigint {
    if (method === "relayPayable" || method === "relayBalancePayable") return HandoffFunded;
    if (method === "executePayable") return 0x03n;
    if (["authorize", "unauthorize", "appoint", "dismiss", "allowAssets", "denyAssets", "allowance", "annotate"].includes(method)) {
      return 0x02n;
    }
    if (["depositPayable", "settlePayable", "provisionPayable", "recoverPayable"].includes(method)) {
      return 0x01n;
    }
    return 0n;
  }

  async function remoteCmd(method: string) {
    return commandId(`${method}(bytes)`, remote);
  }

  it("annotates commands with intrinsic semantic actions", async () => {
    const deployment = host.deploymentTransaction();
    expect(deployment).to.not.equal(null);

    for (const [method, action] of [
      ["deposit", 4n],
      ["depositPayable", 4n],
      ["withdraw", 5n],
      ["payout", 2n],
      ["settle", 3n],
      ["settlePayable", 3n],
      ["cashout", 15n],
      ["realize", 17n],
    ] as const) {
      await expect(deployment!).to.emit(host, "Annotation")
        .withArgs(await cmd(method), encodeActionBlock(action));
    }
  });

  // â”€â”€ Deposit â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  describe("deposit", () => {
    it("emits DepositCalled for a single AMOUNT block and returns BALANCE blocks", async () => {
      const asset = ethers.zeroPadValue("0x01", 32);
      const amount = 100n;
      const input = encodeAmountBlock(asset, amount);

      const tx = await callAs(0, "deposit", ctx({ input: input }));
      await expect(tx).to.emit(host, "DepositCalled")
        .withArgs(userAccount, asset, amount);
    });

    it("returns BALANCE blocks matching the deposited amounts", async () => {
      const asset = ethers.zeroPadValue("0x01", 32);
      const amount = 50n;
      const input = encodeAmountBlock(asset, amount);

      const [result, transactions] = await host.deposit.staticCall(...ctx({ input: input }));
      expect(result).to.equal(encodeBalanceBlock(asset, amount));
      expect(transactions).to.equal(0n);
    });

    it("processes multiple AMOUNT blocks", async () => {
      const asset1 = ethers.zeroPadValue("0x01", 32);
      const asset2 = ethers.zeroPadValue("0x02", 32);
      const input = concat(
        encodeAmountBlock(asset1, 10n),
        encodeAmountBlock(asset2, 20n)
      );

      const [result, transactions] = await host.deposit.staticCall(...ctx({ input: input }));
      expect(result).to.equal(concat(
        encodeBalanceBlock(asset1, 10n),
        encodeBalanceBlock(asset2, 20n)
      ));
      expect(transactions).to.equal(0n);
    });

    it("uses the amount actually received from the deposit hook", async () => {
      const asset = ethers.zeroPadValue("0x01", 32);
      await withDepositFee(3n, async () => {
        const [result] = await host.deposit.staticCall(...ctx({ input: encodeAmountBlock(asset, 50n) }));
        expect(result).to.equal(encodeBalanceBlock(asset, 47n));
      });
    });

    it("accepts an ordinary command call from an authorized node", async () => {
      const caller = await deploy("TestExecuteTarget");
      const node = await utils.testToHostId(await caller.getAddress());
      await host.authorize(encodeContextBlock(adminAccount, "0x", encodeNodeBlock(node)));

      const asset = ethers.zeroPadValue("0x03", 32);
      const input = encodeAmountBlock(asset, 25n);
      const data = host.interface.encodeFunctionData("deposit", ctx({ input }));

      await expect(caller.callTarget(await host.getAddress(), data))
        .to.emit(host, "DepositCalled")
        .withArgs(userAccount, asset, 25n);
    });

    it("reverts AccessDenied for untrusted caller", async () => {
      const asset = ethers.zeroPadValue("0x01", 32);
      const input = encodeAmountBlock(asset, 1n);
      await expect(
        callAs(1, "deposit", ctx({ input: input }))
      ).to.be.revertedWithCustomError(host, "AccessDenied");
    });

    it("treats empty input as an empty batch", async () => {
      expect(await host.deposit.staticCall(...ctx())).to.deep.equal(["0x", 0n]);
    });

    it("reverts OutOfBounds for input with only 4 garbage bytes", async () => {
      await expect(
        callAs(0, "deposit", ctx({ input: "0xdeadbeef" }))
      ).to.be.revertedWithCustomError(host, "OutOfBounds");
    });

    it("rejects more than one context block", async () => {
      const input = encodeAmountBlock(ethers.zeroPadValue("0x01", 32), 1n);
      const context = ctx({ input })[0];

      await expect(callAs(0, "deposit", [concat(context, context)]))
        .to.be.revertedWithCustomError(host, "InvalidBlock");
    });

    it("rejects state when the command declares an empty state source", async () => {
      const asset = ethers.zeroPadValue("0x01", 32);
      const liability = ethers.zeroPadValue("0x02", 32);
      const state = encodePositionBlock(asset, 10n, liability, 5n);
      const input = encodeAmountBlock(asset, 10n);

      await expect(callAs(0, "deposit", ctx({ state, input })))
        .to.be.revertedWithCustomError(host, "OutOfBounds");
    });
  });
  describe("depositPayable", () => {
    it("passes a shared value budget through to the hook", async () => {
      const asset1 = ethers.zeroPadValue("0x03", 32);
      const asset2 = ethers.zeroPadValue("0x04", 32);
      const input = concat(
        encodeAmountBlock(asset1, 3n),
        encodeAmountBlock(asset2, 7n)
      );

      const tx = await callAs(0, "depositPayable", ctx({ input: input }), { value: 10n });
      await expect(tx).to.emit(host, "DepositPayableCalled")
        .withArgs(userAccount, asset1, 3n, 7n);
      await expect(tx).to.emit(host, "DepositPayableCalled")
        .withArgs(userAccount, asset2, 7n, 0n);
    });

    it("returns BALANCE blocks matching the deposited amounts", async () => {
      const asset = ethers.zeroPadValue("0x05", 32);
      const input = encodeAmountBlock(asset, 8n);

      const [result, transactions] = await host.depositPayable.staticCall(...ctx({ input: input }), { value: 8n });
      expect(result).to.equal(encodeBalanceBlock(asset, 8n));
      expect(transactions).to.equal(0n);
    });

    it("returns output and remaining native credit separately", async () => {
      const asset = ethers.zeroPadValue("0x06", 32);
      const input = encodeAmountBlock(asset, 8n);

      const [result, transactions] = await host.depositPayable.staticCall(...ctx({ input: input }), { value: 9n });
      expect(result).to.equal(encodeBalanceBlock(asset, 8n));
      expect(transactions).to.equal(1n);
    });

    it("uses the amount actually received from the payable deposit hook", async () => {
      const asset = ethers.zeroPadValue("0x05", 32);
      await withDepositFee(2n, async () => {
        const [result, credit] = await host.depositPayable.staticCall(
          ...ctx({ input: encodeAmountBlock(asset, 8n) }),
          { value: 8n },
        );
        expect(result).to.equal(encodeBalanceBlock(asset, 6n));
        expect(credit).to.equal(0n);
      });
    });

    it("keeps plain deposit values full-width", async () => {
      const asset = ethers.zeroPadValue("0x07", 32);
      const input = encodeAmountBlock(asset, 1n << 128n);

      await expect(callAs(0, "depositPayable", ctx({ input })))
        .to.be.revertedWithCustomError(host, "InsufficientValue");
    });

  });


  // â”€â”€ Withdraw â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  describe("withdraw", () => {
    const asset = ethers.zeroPadValue("0x10", 32);

    it("emits WithdrawCalled for BALANCE blocks in state", async () => {
      const state = encodeBalanceBlock(asset, 100n);
      const tx = await callAs(0, "withdraw", ctx({ state }));
      await expect(tx).to.emit(host, "WithdrawCalled")
        .withArgs(userAccount, asset, 100n);
    });

    it("treats empty state as an empty batch", async () => {
      expect(await host.withdraw.staticCall(...ctx())).to.deep.equal(["0x", 0n]);
    });

    it("emits WithdrawCalled for each BALANCE block in a batch state", async () => {
      const asset1 = ethers.zeroPadValue("0x11", 32);
      const asset2 = ethers.zeroPadValue("0x12", 32);
      const asset3 = ethers.zeroPadValue("0x13", 32);
      const state = concat(
        encodeBalanceBlock(asset1, 10n),
        encodeBalanceBlock(asset2, 20n),
        encodeBalanceBlock(asset3, 30n),
      );
      const tx = await callAs(0, "withdraw", ctx({ state }));
      await expect(tx).to.emit(host, "WithdrawCalled").withArgs(userAccount, asset1, 10n);
      await expect(tx).to.emit(host, "WithdrawCalled").withArgs(userAccount, asset2, 20n);
      await expect(tx).to.emit(host, "WithdrawCalled").withArgs(userAccount, asset3, 30n);
    });

    it("reverts OutOfBounds for state with a truncated BALANCE block", async () => {
      const full = encodeBalanceBlock(asset, 100n);
      const truncated = ethers.hexlify(ethers.getBytes(full).slice(0, -1));
      await expect(callAs(0, "withdraw", ctx({ state: truncated })))
        .to.be.revertedWithCustomError(host, "OutOfBounds");
    });
  });

  describe("bootstrap", () => {
    it("discovers pipeline-local BOOTSTRAP input with BALANCE output", async () => {
      expect(host.interface.getFunction("bootstrap")).to.equal(null);
      const deployment = host.deploymentTransaction();
      expect(deployment).to.not.equal(null);

      await expect(deployment!).to.emit(host, "Endpoint")
        .withArgs(
          await host.host(),
          await cmd("bootstrap"),
          endpointDescriptor({ input: Keys.Bootstrap, inputHint: 96, output: exactSpec(Keys.Balance, 64) }),
        );
    });
  });

  describe("cashout", () => {
    it("discovers BALANCE state with empty input and output", async () => {
      const deployment = host.deploymentTransaction();
      expect(deployment).to.not.equal(null);

      await expect(deployment!).to.emit(host, "Endpoint")
        .withArgs(
          await host.host(),
          await cmd("cashout"),
          endpointDescriptor({ state: Keys.Balance, stateHint: 64 }),
        );
    });

    it("withdraws chain-asset BALANCE state through its hook", async () => {
      const chainAsset = await utils.testToChain();
      const state = encodeBalanceBlock(chainAsset, 25n);
      const tx = await callAs(0, "cashout", ctx({ state }));

      await expect(tx).to.emit(host, "CashoutCalled")
        .withArgs(userAccount, 25n);
      expect(await host.cashout.staticCall(...ctx({ state })))
        .to.deep.equal(["0x", 0n]);
    });

    it("cashes out batches and accepts an empty batch", async () => {
      const chainAsset = await utils.testToChain();
      const state = concat(
        encodeBalanceBlock(chainAsset, 3n),
        encodeBalanceBlock(chainAsset, 5n),
      );
      const tx = await callAs(0, "cashout", ctx({ state }));
      await expect(tx).to.emit(host, "CashoutCalled").withArgs(userAccount, 3n);
      await expect(tx).to.emit(host, "CashoutCalled").withArgs(userAccount, 5n);
      expect(await host.cashout.staticCall(...ctx({ state }))).to.deep.equal(["0x", 0n]);
      expect(await host.cashout.staticCall(...ctx())).to.deep.equal(["0x", 0n]);
    });

    it("rejects non-chain-asset BALANCE state", async () => {
      const state = encodeBalanceBlock(ethers.ZeroHash, 1n);
      await expect(callAs(0, "cashout", ctx({ state })))
        .to.be.revertedWithCustomError(host, "InvalidAsset");
    });
  });

  it("omits optional repayment and legacy debt commands from this host", async () => {
    for (const method of ["repay", "repayPayable", "repayPosition", "repayPositionPayable", "realizeDebt", "realizePosition"]) {
      expect(host.interface.getFunction(`${method}(bytes)`)).to.equal(null);
    }
  });

  it("rejects account and host-node counterparties in the realization override", async () => {
    const asset = ethers.zeroPadValue("0x20", 32);
    const liability = ethers.zeroPadValue("0x21", 32);
    for (const counterparty of [userAccount, ethers.toBeHex(await host.host(), 32)]) {
      const state = encodePositionBlock(asset, 10n, liability, 7n, counterparty);
      const input = encodeLimitsBlock(10n, 7n);
      await expect(callAs(0, "realize", ctx({ state, input })))
        .to.be.revertedWithCustomError(host, "UnexpectedValue");
    }
  });

  it("delegates counterparty validation to overridden settlement hooks in every execution path", async () => {
    const asset = ethers.zeroPadValue("0x20", 32);
    const liability = ethers.zeroPadValue("0x21", 32);
    for (const counterparty of [ethers.ZeroHash, asset, ethers.toBeHex(await host.host(), 32)]) {
      // The override controls acceptance, including values the default hook rejects.
      await host.setAcceptedSettleCounterparty(counterparty);
      try {
        for (const amount of [0n, 10n]) {
          const state = encodePositionBlock(asset, amount, liability, amount, counterparty);
          for (const method of ["settle", "settlePayable"]) {
            await expect(callAs(0, method, ctx({ state }), { value: method === "settlePayable" ? amount * 2n : 0n }))
              .to.emit(host, "SettleCounterpartyChecked").withArgs(counterparty);
          }
          await expect(callAs(0, "testPipe", userAccount, state,
            encodeStepBlock(await cmd("settle"), 0n, "0x")))
            .to.emit(host, "SettleCounterpartyChecked").withArgs(counterparty);
        }
      } finally {
        await host.setAcceptedSettleCounterparty(userAccount);
      }
    }
  });

  it("leaves account-counterparty authorization to settlement hooks", async () => {
    const asset = ethers.zeroPadValue("0x20", 32);
    const liability = ethers.zeroPadValue("0x21", 32);
    for (const counterparty of [userAccount, encodeUserAccount("0x22")]) {
      const state = encodePositionBlock(asset, 0n, liability, 0n, counterparty);
      for (const method of ["settle", "settlePayable", "testPipe"]) {
        const tx = method === "testPipe"
          ? callAs(0, method, userAccount, state, encodeStepBlock(await cmd("settle"), 0n, "0x"))
          : callAs(0, method, ctx({ state }));
        if (counterparty === userAccount) await expect(tx)
          .to.emit(host, "SettleCounterpartyChecked").withArgs(userAccount);
        else await expect(tx).to.be.revertedWithCustomError(host, "UnexpectedValue");
      }
    }
  });

  for (const method of ["settle", "settlePayable", "memory"]) {
    describe(`${method} empty input`, () => {
      const asset = ethers.toBeHex(1, 32);
      const liability = ethers.toBeHex(2, 32);
      function run(input: string) {
        const position = encodePositionBlock(asset, 100n, liability, 40n, userAccount);
        const state = concat(position, position);
        return method === "memory"
          ? cmd("settle").then(id => callAs(0, "testPipe", userAccount, state, encodeStepBlock(id, 0n, input)))
          : callAs(0, method, ctx({ state, input }), method === "settlePayable" ? { value: 280n } : {});
      }
      it("settles a batch without limits input", async () => {
        await expect(run("0x"))
          .to.emit(host, method === "settlePayable" ? "SettlePayableCalled" : "SettleCalled");
      });
      it("rejects any input", async () => {
        for (const input of [encodeLimitsBlock(100n, 40n), "0x01", encodeAmountBlock(asset, 1n)]) {
          await expect(run(input)).to.be.revertedWithCustomError(host, method === "memory" ? "UnexpectedInput" : "OutOfBounds");
        }
      });
    });
  }

  it("settles liability-only positions through calldata and funded settlement", async () => {
    const liability = ethers.zeroPadValue("0x21", 32);
    const state = encodePositionBlock(ethers.ZeroHash, 0n, liability, 7n, userAccount);
    await expect(callAs(0, "settle", ctx({ state }))).to.emit(host, "SettleCalled")
      .withArgs(userAccount, ethers.ZeroHash, 0n, liability, 7n);
    expect(await host.settle.staticCall(...ctx({ state }))).to.deep.equal(["0x", 0n]);
    expect(await host.settlePayable.staticCall(...ctx({ state }), { value: 9n }))
      .to.deep.equal(["0x", 2n]);
    await expect(callAs(0, "settlePayable", ctx({ state }), { value: 6n }))
      .to.be.revertedWithCustomError(host, "InsufficientValue");
  });

  it("repays batches of liability-only positions through funded settlement", async () => {
    const liability = ethers.zeroPadValue("0x21", 32);
    const state = concat(encodePositionBlock(ethers.ZeroHash, 0n, liability, 7n, userAccount), encodePositionBlock(ethers.ZeroHash, 0n, liability, 8n, userAccount));
    expect(await host.settlePayable.staticCall(...ctx({ state }), { value: 20n }))
      .to.deep.equal(["0x", 5n]);
    const tx = await callAs(0, "settlePayable", ctx({ state }), { value: 20n });
    await expect(tx).to.emit(host, "SettlePayableCalled")
      .withArgs(userAccount, ethers.ZeroHash, 0n, liability, 7n, 13n);
    await expect(tx).to.emit(host, "SettlePayableCalled")
      .withArgs(userAccount, ethers.ZeroHash, 0n, liability, 8n, 5n);
    await expect(callAs(0, "settlePayable", ctx({ state }), { value: 14n }))
      .to.be.revertedWithCustomError(host, "InsufficientValue");
  });

  describe("settle", () => {
    const asset = ethers.zeroPadValue("0x20", 32);
    const liability = ethers.zeroPadValue("0x21", 32);

    it("discovers POSITION state with empty input and output", async () => {
      const deployment = host.deploymentTransaction();
      expect(deployment).to.not.equal(null);

      await expect(deployment!).to.emit(host, "Endpoint")
        .withArgs(
          await host.host(),
          await cmd("settle"),
          endpointDescriptor({ state: Keys.Position, stateHint: 160 }),
        );
    });

    it("passes each POSITION value and the acting account to the hook", async () => {
      const state = encodePositionBlock(asset, 100n, liability, 40n, userAccount);
      const tx = await callAs(0, "settle", ctx({ state }));

      await expect(tx).to.emit(host, "SettleCalled")
        .withArgs(userAccount, asset, 100n, liability, 40n);

      const [output, transactions] = await host.settle.staticCall(...ctx({ state }));
      expect(output).to.equal("0x");
      expect(transactions).to.equal(0n);
    });

    it("settles a batch of POSITION blocks", async () => {
      const secondAsset = ethers.zeroPadValue("0x22", 32);
      const secondLiability = ethers.zeroPadValue("0x23", 32);
      const state = concat(
        encodePositionBlock(asset, 100n, liability, 40n, userAccount),
        encodePositionBlock(secondAsset, 200n, secondLiability, 75n, userAccount),
      );
      const tx = await callAs(0, "settle", ctx({ state }));

      await expect(tx).to.emit(host, "SettleCalled")
        .withArgs(userAccount, asset, 100n, liability, 40n);
      await expect(tx).to.emit(host, "SettleCalled")
        .withArgs(userAccount, secondAsset, 200n, secondLiability, 75n);
    });

    it("treats empty state as an empty batch", async () => {
      expect(await host.settle.staticCall(...ctx())).to.deep.equal(["0x", 0n]);
    });

    it("reverts OutOfBounds for truncated POSITION state", async () => {
      const full = encodePositionBlock(asset, 100n, liability, 40n, userAccount);
      const truncated = ethers.hexlify(ethers.getBytes(full).slice(0, -1));
      await expect(callAs(0, "settle", ctx({ state: truncated })))
        .to.be.revertedWithCustomError(host, "OutOfBounds");
    });

    it("reverts AccessDenied for an untrusted caller", async () => {
      const state = encodePositionBlock(asset, 100n, liability, 40n, userAccount);
      await expect(callAs(1, "settle", ctx({ state })))
        .to.be.revertedWithCustomError(host, "AccessDenied");
    });

    it("rejects input with the wrong schema", async () => {
      const state = encodePositionBlock(asset, 100n, liability, 40n, userAccount);
      const input = encodeAmountBlock(asset, 1n);

      await expect(callAs(0, "settle", ctx({ state, input })))
        .to.be.revertedWithCustomError(host, "OutOfBounds");
    });
  });

  describe("settlePayable", () => {
    const asset = ethers.zeroPadValue("0x24", 32);
    const liability = ethers.zeroPadValue("0x25", 32);

    it("discovers a funded command with POSITION state", async () => {
      const deployment = host.deploymentTransaction();
      expect(deployment).to.not.equal(null);

      await expect(deployment!).to.emit(host, "Endpoint")
        .withArgs(
          await host.host(),
          await cmd("settlePayable"),
          endpointDescriptor({ state: Keys.Position, stateHint: 160, funded: true }),
        );
    });

    it("passes one shared value budget through a batch", async () => {
      const secondAsset = ethers.zeroPadValue("0x26", 32);
      const secondLiability = ethers.zeroPadValue("0x27", 32);
      const state = concat(
        encodePositionBlock(asset, 100n, liability, 40n, userAccount),
        encodePositionBlock(secondAsset, 20n, secondLiability, 10n, userAccount),
      );
      const tx = await callAs(0, "settlePayable", ctx({ state }), { value: 200n });

      await expect(tx).to.emit(host, "SettlePayableCalled")
        .withArgs(userAccount, asset, 100n, liability, 40n, 60n);
      await expect(tx).to.emit(host, "SettlePayableCalled")
        .withArgs(userAccount, secondAsset, 20n, secondLiability, 10n, 30n);
    });

    it("returns unspent command value as native budget credit", async () => {
      const state = encodePositionBlock(asset, 3n, liability, 2n, userAccount);
      const [output, transactions] = await host.settlePayable.staticCall(
        ...ctx({ state }),
        { value: 8n },
      );

      expect(output).to.equal("0x");
      expect(transactions).to.equal(3n);
    });

    it("reverts InsufficientValue when the hook overspends the budget", async () => {
      const state = encodePositionBlock(asset, 3n, liability, 2n, userAccount);

      await expect(callAs(0, "settlePayable", ctx({ state }), { value: 4n }))
        .to.be.revertedWithCustomError(host, "InsufficientValue");
    });

    it("treats empty state as an empty batch", async () => {
      expect(await host.settlePayable.staticCall(...ctx())).to.deep.equal(["0x", 0n]);
    });

    it("reverts AccessDenied for an untrusted caller", async () => {
      const state = encodePositionBlock(asset, 3n, liability, 2n, userAccount);

      await expect(callAs(1, "settlePayable", ctx({ state }), { value: 5n }))
        .to.be.revertedWithCustomError(host, "AccessDenied");
    });

    it("rejects input with the wrong schema", async () => {
      const state = encodePositionBlock(asset, 3n, liability, 2n, userAccount);
      const input = encodeAmountBlock(asset, 1n);

      await expect(callAs(0, "settlePayable", ctx({ state, input }), { value: 5n }))
        .to.be.revertedWithCustomError(host, "OutOfBounds");
    });
  });

  describe("payout", () => {
    const asset = ethers.zeroPadValue("0x28", 32);

    it("emits PayoutCalled for paired BALANCE state and ACCOUNT input blocks", async () => {
      const to = encodeUserAccount("0xd00d");
      const state = encodeBalanceBlock(asset, 250n);
      const input = encodeAccountBlock(to);
      const tx = await callAs(0, "payout", ctx({ state, input: input }));

      await expect(tx).to.emit(host, "PayoutCalled")
        .withArgs(userAccount, to, asset, 250n);
    });

    it("pairs each BALANCE block with the matching ACCOUNT block", async () => {
      const asset1 = ethers.zeroPadValue("0x29", 32);
      const asset2 = ethers.zeroPadValue("0x2a", 32);
      const to1 = encodeUserAccount("0xd001");
      const to2 = encodeUserAccount("0xd002");
      const state = concat(
        encodeBalanceBlock(asset1, 10n),
        encodeBalanceBlock(asset2, 20n),
      );
      const input = concat(
        encodeAccountBlock(to1),
        encodeAccountBlock(to2),
      );
      const tx = await callAs(0, "payout", ctx({ state, input: input }));

      await expect(tx).to.emit(host, "PayoutCalled").withArgs(userAccount, to1, asset1, 10n);
      await expect(tx).to.emit(host, "PayoutCalled").withArgs(userAccount, to2, asset2, 20n);
    });

    it("reverts OutOfBounds when input accounts run out before state balances", async () => {
      const state = concat(
        encodeBalanceBlock(asset, 1n),
        encodeBalanceBlock(asset, 2n),
      );
      const input = encodeAccountBlock(encodeUserAccount("0xd003"));

      await expect(callAs(0, "payout", ctx({ state, input: input })))
        .to.be.revertedWithCustomError(host, "OutOfBounds");
    });

    it("reverts InvalidBlock when the paired input block is not an ACCOUNT", async () => {
      const state = encodeBalanceBlock(asset, 1n);
      const input = encodeBalanceBlock(asset, 1n);

      await expect(callAs(0, "payout", ctx({ state, input: input })))
        .to.be.revertedWithCustomError(host, "InvalidBlock");
    });
  });

  // â”€â”€ CreditTo â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  describe("realize", () => {
    function positionInput(minimum = 0n, maximum = MaxUint128) {
      return encodeLimitsBlock(minimum, maximum);
    }
    const asset = ethers.zeroPadValue("0x21", 32);
    const liability = ethers.zeroPadValue("0x22", 32);
    const toAsset = asset;
    const toLiability = liability;

    it("discovers POSITION state, LIMITS input, and POSITION output", async () => {
      const deployment = host.deploymentTransaction();
      expect(deployment).to.not.equal(null);

      await expect(deployment!).to.emit(host, "Endpoint")
        .withArgs(
          await host.host(),
          await cmd("realize"),
          endpointDescriptor({
            state: Keys.Position, stateHint: 160,
            input: Keys.Limits, inputHint: 32,
            output: exactSpec(Keys.Position, 160),
          }),
        );
    });

    it("rejects the former BALANCE state shape", async () => {
      await expect(callAs(0, "realize", ctx({
        state: encodeBalanceBlock(asset, 100n),
        input: positionInput(),
      }))).to.be.revertedWithCustomError(host, "OutOfBounds");
    });

    it("passes the entire position to a single hook", async () => {
      const state = encodePositionBlock(asset, 100n, liability, 80n, encodeHostAccount(await host.host()));
      const input = positionInput(90n, 85n);
      const tx = await callAs(0, "realize", ctx({ state, input }));

      await expect(tx).to.emit(host, "RealizeCalled")
        .withArgs(userAccount, asset, 100n, liability, 80n, encodeHostAccount(await host.host()));
      expect(await host.realize.staticCall(...ctx({ state, input }))).to.deep.equal([
        encodePositionBlock(toAsset, 100n, toLiability, 80n),
        0n,
      ]);
    });

    it("emits the position returned by the realization hook", async () => {
      await withRealizeFee(4n, async () => {
        await withRealizeDebtFee(3n, async () => {
          const [result] = await host.realize.staticCall(...ctx({
            state: encodePositionBlock(asset, 100n, liability, 80n, encodeHostAccount(await host.host())),
            input: positionInput(96n, 77n),
          }));
          expect(result).to.equal(encodePositionBlock(toAsset, 96n, toLiability, 77n));
        });
      });
    });

    it("pairs positions and quantity limits by position", async () => {
      const asset2 = ethers.zeroPadValue("0x25", 32);
      const liability2 = ethers.zeroPadValue("0x26", 32);
      const toAsset2 = asset2;
      const toLiability2 = liability2;
      const state = concat(
        encodePositionBlock(asset, 10n, liability, 8n, encodeHostAccount(await host.host())),
        encodePositionBlock(asset2, 20n, liability2, 16n, encodeHostAccount(await host.host())),
      );
      const input = concat(
        positionInput(10n, 8n),
        positionInput(20n, 16n),
      );

      const [result, credit] = await host.realize.staticCall(...ctx({ state, input }));
      expect(result).to.equal(concat(
        encodePositionBlock(toAsset, 10n, toLiability, 8n),
        encodePositionBlock(toAsset2, 20n, toLiability2, 16n),
      ));
      expect(credit).to.equal(0n);
    });

    it("validates LIMITS headers before quantities and bounds every input block", async () => {
      const state = encodePositionBlock(asset, 0n, liability, 100n, encodeHostAccount(await host.host()));
      const limits = encodeLimitsBlock(1n, 0n);
      for (const input of ["0xffffffff" + limits.slice(10), limits.slice(0, 10) + "0000001f" + limits.slice(18)]) {
        await expect(callAs(0, "realize", ctx({ state, input })))
          .to.be.revertedWithCustomError(host, "InvalidBlock");
      }
      await expect(callAs(0, "realize", ctx({ state, input: ethers.dataSlice(limits, 0, 39) })))
        .to.be.revertedWithCustomError(host, "OutOfBounds");
      await expect(callAs(0, "realize", ctx({ state, input: concat(positionInput(), positionInput()) })))
        .to.be.revertedWithCustomError(host, "OutOfBounds");
    });

    it("accepts empty streams and rejects malformed pairings", async () => {
      expect(await host.realize.staticCall(...ctx())).to.deep.equal(["0x", 0n]);

      await expect(callAs(0, "realize", ctx({
        state: encodePositionBlock(asset, 1n, liability, 1n, encodeHostAccount(await host.host())),
      }))).to.be.revertedWithCustomError(host, "OutOfBounds");
      await expect(callAs(0, "realize", ctx({
        state: encodePositionBlock(asset, 1n, liability, 1n, encodeHostAccount(await host.host())),
        input: encodeAssetBlock(toAsset),
      }))).to.be.revertedWithCustomError(host, "InvalidBlock");
      await expect(callAs(0, "realize", ctx({
        input: positionInput(),
      }))).to.be.revertedWithCustomError(host, "OutOfBounds");
    });
  });

  describe("realization limits", () => {
    const from = ethers.zeroPadValue("0x41", 32);
    const to = from;
    for (const side of ["asset", "debt"] as const) {
      const encodeState = (asset: string, amount: bigint) => side === "asset"
        ? encodePositionBlock(asset, amount, ethers.ZeroHash, 0n)
        : encodeLiabilityPosition(asset, amount);
      const encodeInput = (limit: bigint) => side === "asset"
        ? encodeLimitsBlock(limit, MaxUint128)
        : encodeLimitsBlock(0n, limit);
      for (const [amount, limit] of [
        [10n, 9n], [10n, 10n], [10n, 11n], [10n, 0n], [10n, MaxUint128],
        [0n, 0n], [0n, 1n], [MaxUint128, MaxUint128],
        [MaxUint128 + 1n, MaxUint128], [ethers.MaxUint256, MaxUint128],
      ]) {
        it(`${side} checks limit ${limit} against output ${amount}`, async () => {
          const args = ctx({ state: encodePositionBlock(side === "asset" ? from : ethers.ZeroHash, side === "asset" ? amount : 0n, side === "debt" ? from : ethers.ZeroHash, side === "debt" ? amount : 0n, encodeHostAccount(await host.host())), input: encodeInput(limit) });
          const fails = side === "asset" ? amount < limit : amount > limit;
          if (fails) {
            await expect(callAs(0, "realize", args)).to.be.revertedWithCustomError(host, "OutOfRange");
          } else {
            expect(await host.realize.staticCall(...args)).to.deep.equal([encodeState(to, amount), 0n]);
          }
        });
      }

      it(`${side} checks the limit against the hook?s adjusted result`, async () => {
        const withFee = side === "asset" ? withRealizeFee : withRealizeDebtFee;
        await withFee(4n, async () => {
          const state = encodePositionBlock(side === "asset" ? from : ethers.ZeroHash, side === "asset" ? 100n : 0n, side === "debt" ? from : ethers.ZeroHash, side === "debt" ? 100n : 0n, encodeHostAccount(await host.host()));
          expect(await host.realize.staticCall(...ctx({ state, input: encodeInput(96n) })))
            .to.deep.equal([encodeState(to, 96n), 0n]);
          const limit = side === "asset" ? 97n : 95n;
          await expect(callAs(0, "realize", ctx({ state, input: encodeInput(limit) })))
            .to.be.revertedWithCustomError(host, "OutOfRange");
        });
      });
    }
  });

  describe("creditAccount", () => {
    const asset = ethers.zeroPadValue("0x30", 32);

    it("emits CreditToCalled for BALANCE blocks in state", async () => {
      const state = encodeBalanceBlock(asset, 300n);
      const tx = await callAs(0, "creditAccount", ctx({ state }));
      await expect(tx).to.emit(host, "CreditToCalled")
        .withArgs(userAccount, asset, 300n, 300n);
    });

    it("treats empty state as an empty batch", async () => {
      expect(await host.creditAccount.staticCall(...ctx())).to.deep.equal(["0x", 0n]);
    });
  });

  // â”€â”€ DebitFrom â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  describe("debitAccount", () => {
    const asset = ethers.zeroPadValue("0x40", 32);

    it("emits DebitFromCalled and returns BALANCE blocks", async () => {
      const input = encodeAmountBlock(asset, 400n);
      const tx = await callAs(0, "debitAccount", ctx({ input: input }));
      await expect(tx).to.emit(host, "DebitFromCalled")
        .withArgs(userAccount, asset, 400n, 400n);
    });

    it("returns one BALANCE block per AMOUNT block", async () => {
      const input = encodeAmountBlock(asset, 100n);
      const [result, transactions] = await host.debitAccount.staticCall(...ctx({ input: input }));
      expect(result).to.equal(encodeBalanceBlock(asset, 100n));
      expect(transactions).to.equal(0n);
    });

    it("treats empty input as an empty batch", async () => {
      expect(await host.debitAccount.staticCall(...ctx())).to.deep.equal(["0x", 0n]);
    });

    it("processes multiple AMOUNT blocks and emits DebitFromCalled for each", async () => {
      const asset1 = ethers.zeroPadValue("0x41", 32);
      const asset2 = ethers.zeroPadValue("0x42", 32);
      const asset3 = ethers.zeroPadValue("0x43", 32);
      const input = concat(
        encodeAmountBlock(asset1, 100n),
        encodeAmountBlock(asset2, 200n),
        encodeAmountBlock(asset3, 300n),
      );
      const tx = await callAs(0, "debitAccount", ctx({ input: input }));
      await expect(tx).to.emit(host, "DebitFromCalled").withArgs(userAccount, asset1, 100n, 100n);
      await expect(tx).to.emit(host, "DebitFromCalled").withArgs(userAccount, asset2, 200n, 200n);
      await expect(tx).to.emit(host, "DebitFromCalled").withArgs(userAccount, asset3, 300n, 300n);
    });

    it("returns one BALANCE block per AMOUNT block in a batch", async () => {
      const asset1 = ethers.zeroPadValue("0x44", 32);
      const asset2 = ethers.zeroPadValue("0x45", 32);
      const input = concat(
        encodeAmountBlock(asset1, 100n),
        encodeAmountBlock(asset2, 200n),
      );
      const [result, transactions] = await host.debitAccount.staticCall(...ctx({ input: input }));
      expect(result).to.equal(concat(
        encodeBalanceBlock(asset1, 100n),
        encodeBalanceBlock(asset2, 200n),
      ));
      expect(transactions).to.equal(0n);
    });
  });

  // â”€â”€ Fund â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  // â”€â”€ Allocate / Provision â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  describe("allocate", () => {
    it("discovers BALANCE state, NODE input, and CUSTODY output lanes", async () => {
      const deployment = host.deploymentTransaction();
      expect(deployment).to.not.equal(null);

      await expect(deployment!).to.emit(host, "Endpoint")
        .withArgs(
          await host.host(),
          await cmd("allocate"),
          endpointDescriptor({ state: Keys.Balance, stateHint: 64, input: Keys.Node, inputHint: 32, output: exactSpec(Keys.Custody, 96) }),
        );
    });

    it("calls the hook and returns CUSTODY state", async () => {
      const asset = ethers.zeroPadValue("0x60", 32);
      const hostId = 123456n;
      const state = encodeBalanceBlock(asset, 600n);
      const input = encodeNodeBlock(hostId);

      const tx = await callAs(0, "allocate", ctx({ state, input }));
      await expect(tx).to.emit(host, "AllocateCalled")
        .withArgs(hostId, userAccount, asset, 600n);

      const [result, transactions] = await host.allocate.staticCall(...ctx({ state, input }));
      expect(result).to.equal(encodeCustodyBlock(hostId, asset, 600n));
      expect(transactions).to.equal(0n);
    });

    it("pairs each BALANCE with the NODE at the same position", async () => {
      const asset1 = ethers.zeroPadValue("0x61", 32);
      const asset2 = ethers.zeroPadValue("0x62", 32);
      const state = concat(
        encodeBalanceBlock(asset1, 100n),
        encodeBalanceBlock(asset2, 200n),
      );
      const input = concat(encodeNodeBlock(111n), encodeNodeBlock(222n));

      const [result, transactions] = await host.allocate.staticCall(...ctx({ state, input }));
      expect(result).to.equal(concat(
        encodeCustodyBlock(111n, asset1, 100n),
        encodeCustodyBlock(222n, asset2, 200n),
      ));
      expect(transactions).to.equal(0n);
    });

    it("reverts OutOfBounds when NODE input runs out before BALANCE state", async () => {
      const asset = ethers.zeroPadValue("0x63", 32);
      const state = concat(
        encodeBalanceBlock(asset, 100n),
        encodeBalanceBlock(asset, 200n),
      );
      const input = encodeNodeBlock(111n);

      await expect(callAs(0, "allocate", ctx({ state, input })))
        .to.be.revertedWithCustomError(host, "OutOfBounds");
    });

    it("reverts InvalidBlock for non-NODE input", async () => {
      const asset = ethers.zeroPadValue("0x64", 32);
      const state = encodeBalanceBlock(asset, 100n);
      const input = encodeAmountBlock(asset, 100n);

      await expect(callAs(0, "allocate", ctx({ state, input })))
        .to.be.revertedWithCustomError(host, "InvalidBlock");
    });
  });

  describe("provision", () => {
    it("emits ProvisionCalled and returns CUSTODY blocks", async () => {
      const asset = ethers.zeroPadValue("0x70", 32);
      const hostId = 654321n;
      const input = encodeAllocationBlock(hostId, asset, 700n);
      const tx = await callAs(0, "provision", ctx({ input: input }));
      await expect(tx).to.emit(host, "ProvisionCalled")
        .withArgs(hostId, userAccount, asset, 700n);
    });

    it("returns CUSTODY blocks", async () => {
      const asset = ethers.zeroPadValue("0x70", 32);
      const hostId = 654321n;
      const input = encodeAllocationBlock(hostId, asset, 700n);
      const [result, transactions] = await host.provision.staticCall(...ctx({ input: input }));
      expect(result).to.equal(encodeCustodyBlock(hostId, asset, 700n));
      expect(transactions).to.equal(0n);
    });

    it("reverts OutOfBounds when input cannot decode as an ALLOCATION block", async () => {
      const hostId = 654321n;
      const input = encodeNodeBlock(hostId);
      await expect(callAs(0, "provision", ctx({ input: input })))
        .to.be.revertedWithCustomError(host, "OutOfBounds");
    });

    it("emits ProvisionCalled for each ALLOCATION block in a batch", async () => {
      const asset1 = ethers.zeroPadValue("0x71", 32);
      const asset2 = ethers.zeroPadValue("0x72", 32);
      const host1  = 111n;
      const host2  = 222n;
      const input = concat(
        encodeAllocationBlock(host1, asset1, 100n),
        encodeAllocationBlock(host2, asset2, 200n),
      );
      const tx = await callAs(0, "provision", ctx({ input: input }));
      await expect(tx).to.emit(host, "ProvisionCalled").withArgs(host1, userAccount, asset1, 100n);
      await expect(tx).to.emit(host, "ProvisionCalled").withArgs(host2, userAccount, asset2, 200n);
    });

    it("returns one CUSTODY block per input ALLOCATION block in a batch", async () => {
      const asset1 = ethers.zeroPadValue("0x73", 32);
      const asset2 = ethers.zeroPadValue("0x74", 32);
      const host1  = 333n;
      const host2  = 444n;
      const input = concat(
        encodeAllocationBlock(host1, asset1, 100n),
        encodeAllocationBlock(host2, asset2, 200n),
      );
      const [result, transactions] = await host.provision.staticCall(...ctx({ input: input }));
      expect(result).to.equal(concat(
        encodeCustodyBlock(host1, asset1, 100n),
        encodeCustodyBlock(host2, asset2, 200n),
      ));
      expect(transactions).to.equal(0n);
    });
  });
  describe("provisionPayable", () => {
    it("passes a shared value budget through to the allocation hook", async () => {
      const asset1 = ethers.zeroPadValue("0x75", 32);
      const asset2 = ethers.zeroPadValue("0x76", 32);
      const host1 = 555n;
      const host2 = 666n;
      const input = concat(
        encodeAllocationBlock(host1, asset1, 3n),
        encodeAllocationBlock(host2, asset2, 7n),
      );

      const tx = await callAs(0, "provisionPayable", ctx({ input: input }), { value: 10n });
      await expect(tx).to.emit(host, "ProvisionPayableCalled")
        .withArgs(host1, userAccount, asset1, 3n, 7n);
      await expect(tx).to.emit(host, "ProvisionPayableCalled")
        .withArgs(host2, userAccount, asset2, 7n, 0n);
    });

    it("returns one CUSTODY block per input ALLOCATION block", async () => {
      const asset = ethers.zeroPadValue("0x77", 32);
      const hostId = 777n;
      const input = encodeAllocationBlock(hostId, asset, 8n);

      const [result, transactions] = await host.provisionPayable.staticCall(...ctx({ input: input }), { value: 8n });
      expect(result).to.equal(encodeCustodyBlock(hostId, asset, 8n));
      expect(transactions).to.equal(0n);
    });

    it("keeps plain provision values full-width", async () => {
      const asset = ethers.zeroPadValue("0x78", 32);
      const input = encodeAllocationBlock(888n, asset, 1n << 128n);

      await expect(callAs(0, "provisionPayable", ctx({ input })))
        .to.be.revertedWithCustomError(host, "InsufficientValue");
    });

  });


  // â”€â”€ Pipe â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  describe("relayPayable", () => {
    const PORTAL_PREFIX = 0x03020100n;

    function portalNode(id: bigint) {
      return (PORTAL_PREFIX << 224n) | id;
    }

    it("discovers relayPayable with empty state", async () => {
      const deployment = host.deploymentTransaction();
      expect(deployment).to.not.equal(null);

      await expect(deployment!).to.emit(host, "Endpoint")
        .withArgs(
          await host.host(),
          await cmd("relayPayable"),
          endpointDescriptor({ input: Keys.Relay, inputHint: 256, funded: true, handoff: true }),
        );
      await expect(deployment!).to.emit(host, "Annotation")
        .withArgs(await cmd("relayPayable"), encodeLabelBlock(ethers.ZeroHash, "relayPayable"));
      await expect(deployment!).to.emit(host, "Annotation")
        .withArgs(
          await host.host(),
          encodeSchemaBlock(
            RelayInputSpec,
            "uint portal, uint resources",
            ethers.encodeBytes32String("relay.input"),
          ),
        );
    });

    it("passes the destination context fields to the relay hook", async () => {
      const portal = portalNode(31337n);
      const resources = 9n;
      const steps = encodeStepBlock(0n, 0n, "0x1234");
      const input = encodeRelayBlock(encodeRelayInputBlock(portal, resources), steps);
      const [result, transactions] = await host.relayPayable.staticCall(...ctx({ input }));
      expect(result).to.equal("0x");
      expect(transactions).to.equal(0n);

      const tx = await callAs(0, "relayPayable", ctx({ input }));
      await expect(tx).to.emit(host, "RelayCalled")
        .withArgs(portal, resources, userAccount, encodeContextBlock(userAccount, "0x", steps));
    });

    it("reverts when state is supplied", async () => {
      const state = encodeBalanceBlock(ethers.zeroPadValue("0x80", 32), 1n);
      const input = encodeRelayBlock(
        encodeRelayInputBlock(portalNode(31337n), 0n),
        encodeStepBlock(0n, 0n, "0x"),
      );

      await expect(callAs(0, "relayPayable", ctx({ state, input })))
        .to.be.revertedWithCustomError(host, "UnconsumedData");
    });

    it("rejects headerless qualified input fields", async () => {
      const config = encodeRelayInputBlock(portalNode(31337n), 9n);
      const input = encodeRelayBlock(ethers.dataSlice(config, 8), "0x");

      await expect(callAs(0, "relayPayable", ctx({ input })))
        .to.be.revertedWithCustomError(host, "InvalidBlock");
    });

    it("rejects trailing blocks when the implementation expects one input block", async () => {
      const config = encodeRelayInputBlock(portalNode(31337n), 9n);
      const input = encodeRelayBlock(concat(config, config), "0x");

      await expect(callAs(0, "relayPayable", ctx({ input })))
        .to.be.revertedWithCustomError(host, "InvalidBlock");
    });

    it("rejects empty input while decoding its required RELAY block", async () => {
      await expect(callAs(0, "relayPayable", ctx()))
        .to.be.revertedWithCustomError(host, "InvalidBlock");
    });
  });

  describe("relayBalancePayable", () => {
    const PORTAL_PREFIX = 0x03020100n;
    const relayAsset = ethers.zeroPadValue("0x80", 32);

    function portalNode(id: bigint) {
      return (PORTAL_PREFIX << 224n) | id;
    }

    it("discovers relayBalancePayable with BALANCE state", async () => {
      const deployment = host.deploymentTransaction();
      expect(deployment).to.not.equal(null);

      await expect(deployment!).to.emit(host, "Endpoint")
        .withArgs(
          await host.host(),
          await cmd("relayBalancePayable"),
          endpointDescriptor({ state: Keys.Balance, stateHint: 64, input: Keys.Relay, inputHint: 256, funded: true, handoff: true }),
        );
      await expect(deployment!).to.emit(host, "Annotation")
        .withArgs(await cmd("relayBalancePayable"), encodeLabelBlock(ethers.ZeroHash, "relayBalancePayable"));
    });

    it("passes transport input and a complete destination context to the hook", async () => {
      const state = encodeBalanceBlock(relayAsset, 12n);
      const portal = portalNode(31337n);
      const resources = 9n;
      const steps = encodeStepBlock(0n, 0n, "0x1234");
      const input = encodeRelayBlock(encodeRelayInputBlock(portal, resources), steps);
      const [result, transactions] = await host.relayBalancePayable.staticCall(...ctx({ state, input: input }));
      expect(result).to.equal("0x");
      expect(transactions).to.equal(0n);

      const tx = await callAs(0, "relayBalancePayable", ctx({ state, input: input }));
      await expect(tx).to.emit(host, "RelayCalled")
        .withArgs(portal, resources, userAccount, encodeContextBlock(userAccount, state, steps));
    });

    it("rejects empty input while decoding its required RELAY block", async () => {
      const state = encodeBalanceBlock(relayAsset, 1n);
      await expect(callAs(0, "relayBalancePayable", ctx({ state })))
        .to.be.revertedWithCustomError(host, "InvalidBlock");
    });

    it("forwards an empty raw state source", async () => {
      const input = encodeRelayBlock(
        encodeRelayInputBlock(portalNode(31337n), 0n),
        encodeStepBlock(0n, 0n, "0x"),
      );
      await expect(callAs(0, "relayBalancePayable", ctx({ input })))
        .to.emit(host, "RelayCalled");
    });

    it("reverts AccessDenied for untrusted caller", async () => {
      const portal = portalNode(31337n);
      const input = encodeRelayBlock(
        encodeRelayInputBlock(portal, 0n),
        encodeStepBlock(0n, 0n, "0x"),
      );

      await expect(callAs(1, "relayBalancePayable", ctx({ input: input })))
        .to.be.revertedWithCustomError(host, "AccessDenied");
    });

    it("reverts InvalidBlock when input is not a RELAY block", async () => {
      const asset = ethers.zeroPadValue("0x81", 32);
      const state = encodeBalanceBlock(relayAsset, 1n);
      const input = encodeAmountBlock(asset, 1n);

      await expect(callAs(0, "relayBalancePayable", ctx({ state, input })))
        .to.be.revertedWithCustomError(host, "InvalidBlock");
    });

    it("rejects POSITION state", async () => {
      const state = encodePositionBlock(relayAsset, 1n, relayAsset, 1n);
      const portal = portalNode(31337n);
      const steps = encodeStepBlock(0n, 0n, "0x");
      const input = encodeRelayBlock(encodeRelayInputBlock(portal, 0n), steps);

      await expect(callAs(0, "relayBalancePayable", ctx({ state, input })))
        .to.be.revertedWithCustomError(host, "InvalidBlock");
    });

    it("rejects mixed trailing state blocks", async () => {
      const state = concat(
        encodeBalanceBlock(relayAsset, 1n),
        encodePositionBlock(relayAsset, 1n, relayAsset, 1n),
      );
      const portal = portalNode(31337n);
      const steps = encodeStepBlock(0n, 0n, "0x");
      const input = encodeRelayBlock(encodeRelayInputBlock(portal, 0n), steps);

      await expect(callAs(0, "relayBalancePayable", ctx({ state, input })))
        .to.be.revertedWithCustomError(host, "InvalidBlock");
    });

    for (const [label, malformed, error] of [
      ["wrong BALANCE payload size", (state: string) => state.slice(0, 10) + "0000003f" + state.slice(18), "InvalidBlock"],
      ["truncated BALANCE payload", (state: string) => state.slice(0, -2), "OutOfBounds"],
      ["trailing partial header", (state: string) => state + "00", "OutOfBounds"],
    ] as const) {
      it(`rejects ${label}`, async () => {
        const state = malformed(encodeBalanceBlock(relayAsset, 1n));
        const input = encodeRelayBlock(
          encodeRelayInputBlock(portalNode(31337n), 0n),
          encodeStepBlock(0n, 0n, "0x"),
        );
        await expect(callAs(0, "relayBalancePayable", ctx({ state, input })))
          .to.be.revertedWithCustomError(host, error);
      });
    }

    it("rejects unread trailing RELAY input when closing", async () => {
      const portal = portalNode(31337n);
      const input = concat(
        encodeRelayBlock(encodeRelayInputBlock(portal, 0n), encodeStepBlock(0n, 0n, "0x")),
        encodeRelayBlock(encodeRelayInputBlock(portal, 0n), encodeStepBlock(0n, 0n, "0x"))
      );
      const state = encodeBalanceBlock(relayAsset, 1n);

      await expect(callAs(0, "relayBalancePayable", ctx({ state, input })))
        .to.be.revertedWithCustomError(host, "UnconsumedData");
    });

    it("forwards multiple raw state blocks with one RELAY block", async () => {
      const secondAsset = ethers.zeroPadValue("0x82", 32);
      const state = concat(
        encodeBalanceBlock(relayAsset, 1n),
        encodeBalanceBlock(secondAsset, 2n),
      );
      const portal = portalNode(31337n);
      const steps = encodeStepBlock(0n, 0n, "0x");
      const input = encodeRelayBlock(encodeRelayInputBlock(portal, 0n), steps);

      await expect(callAs(0, "relayBalancePayable", ctx({ state, input })))
        .to.emit(host, "RelayCalled")
        .withArgs(portal, 0n, userAccount, encodeContextBlock(userAccount, state, steps));
    });

    it("passes relay resources through even when it exceeds msg.value", async () => {
      const portal = portalNode(31337n);
      const steps = encodeStepBlock(0n, 0n, "0x");
      const input = encodeRelayBlock(encodeRelayInputBlock(portal, 2n), steps);
      const state = encodeBalanceBlock(relayAsset, 1n);
      const tx = await callAs(0, "relayBalancePayable", ctx({ state, input }));
      await expect(tx).to.emit(host, "RelayCalled")
        .withArgs(portal, 2n, userAccount, encodeContextBlock(userAccount, state, steps));
    });

    it("returns unspent command value after relay dispatch as credit", async () => {
      const portal = portalNode(31337n);
      const input = encodeRelayBlock(
        encodeRelayInputBlock(portal, 0n),
        encodeStepBlock(0n, 0n, "0x"),
      );
      const state = encodeBalanceBlock(relayAsset, 1n);

      const [output, transactions] = await host.relayBalancePayable.staticCall(...ctx({ state, input }), { value: 1n });
      expect(output).to.equal("0x");
      expect(transactions).to.equal(1n);
    });
  });

  describe("relay state safety", () => {
    const asset = ethers.zeroPadValue("0x80", 32);
    const liability = ethers.zeroPadValue("0x81", 32);
    const portal = (0x03020100n << 224n) | 31337n;
    const balance = encodeBalanceBlock(asset, 12n);
    const balances = concat(balance, encodeBalanceBlock(liability, 34n));
    const transport = encodeRelayInputBlock(portal, 0n);
    const continuation = encodeStepBlock(0n, 0n, "0x1234");
    const input = encodeRelayBlock(transport, continuation);
    async function expectPipelineRevert(method: string, state: string, steps: string, errorName: string) {
      let data: string | undefined;
      try {
        await callAs(0, "testPipe", userAccount, state, steps, { value: 1n });
      } catch (error: any) {
        data = error.data ?? error.info?.error?.data;
      }
      expect(data, "pipeline must revert with encoded failure data").to.be.a("string");
      const errors = new ethers.Interface(["error FailedCall(address addr, bytes4 selector, bytes err)"]);
      const failure = errors.parseError(data!);
      expect(failure?.name).to.equal("FailedCall");
      expect(failure?.args).to.deep.equal([
        await host.getAddress(),
        host.interface.getFunction(method)!.selector,
        host.interface.encodeErrorResult(errorName),
      ]);
    }

    const forbidden = [
      ["POSITION with debt", encodePositionBlock(asset, 12n, liability, 7n)],
      ["POSITION with debt and zero assets", encodePositionBlock(asset, 0n, liability, 7n)],
      ["POSITION with maximum debt", encodePositionBlock(asset, 12n, liability, ethers.MaxUint256)],
      ["POSITION with zero debt", encodePositionBlock(asset, 12n, liability, 0n)],
      ["liability-only POSITION", encodeLiabilityPosition(liability, 7n)],
      ["CUSTODY", encodeCustodyBlock(portal, asset, 12n)],
      // AMOUNT has the same payload size as BALANCE, but must still be rejected.
      ["AMOUNT", encodeAmountBlock(asset, 12n)],
      ["unknown block key", "0xffffffff" + balance.slice(10)],
    ] as const;

    for (const method of ["relayPayable", "relayBalancePayable"] as const) {
      describe(method, () => {
        const schemaError = method === "relayPayable" ? "UnconsumedData" : "InvalidBlock";

        for (const [kind, block] of forbidden) {
          for (const [placement, state] of [
            ["alone", block],
            ["before balances", concat(block, balances)],
            ["between balances", concat(balance, block, balance)],
            ["after balances", concat(balances, block)],
          ] as const) {
            it(`rejects ${kind} ${placement}`, async () => {
              await expect(callAs(0, method, ctx({ state, input }), { value: 1n }))
                .to.be.revertedWithCustomError(host, schemaError);
            });
          }
        }

        // Exercise every partial header length and representative partial payloads.
        for (const length of [1, 2, 3, 4, 5, 6, 7, 8, 39, 71]) {
          for (const prefix of ["0x", balances]) {
            it(`rejects a ${length}-byte truncated BALANCE ${prefix === "0x" ? "alone" : "after balances"}`, async () => {
              const state = concat(prefix, ethers.dataSlice(balance, 0, length));
              await expect(callAs(0, method, ctx({ state, input })))
                .to.be.revertedWithCustomError(host, method === "relayPayable" ? "UnconsumedData" : "OutOfBounds");
            });
          }
        }

        for (const size of [0, 32, 63, 65, 128, 0xffffffff]) {
          it(`rejects a BALANCE declaring ${size} payload bytes after valid balances`, async () => {
            const malformed = concat(ethers.dataSlice(balance, 0, 4), ethers.toBeHex(size, 4), ethers.dataSlice(balance, 8));
            await expect(callAs(0, method, ctx({ state: concat(balances, malformed), input })))
              .to.be.revertedWithCustomError(host, schemaError);
          });
        }

        for (const [kind, state] of forbidden) {
          it(`reverts the pipeline handoff for ${kind} after balances`, async () => {
            const steps = concat(
              encodeStepBlock(await cmd(method), 1n, transport),
              encodeStepBlock(await remoteCmd("noop"), 0n, "0x"),
            );
            await expectPipelineRevert(method, concat(balances, state), steps, schemaError);
          });
        }

        it("rejects a second RELAY instead of handing state off twice", async () => {
          const state = method === "relayPayable" ? "0x" : balances;
          await expect(callAs(0, method, ctx({ state, input: concat(input, input) })))
            .to.be.revertedWithCustomError(host, "UnconsumedData");
        });

        it("hands valid state off exactly once and leaves the continuation for the destination", async () => {
          const state = method === "relayPayable" ? "0x" : balances;
          const remaining = encodeStepBlock(await remoteCmd("noop"), 0n, "0x1234");
          const steps = concat(encodeStepBlock(await cmd(method), 0n, transport), remaining);
          const tx = await callAs(0, "testPipe", userAccount, state, steps);
          await expect(tx).to.emit(host, "RelayCalled")
            .withArgs(portal, 0n, userAccount, encodeContextBlock(userAccount, state, remaining));
          const receipt = await tx.wait();
          const relayTopic = host.interface.getEvent("RelayCalled")!.topicHash;
          const commandTopic = remote.interface.getEvent("CommandCalled")!.topicHash;
          expect(receipt!.logs.filter((log) => log.topics[0] === relayTopic)).to.have.length(1);
          expect(receipt!.logs.filter((log) => log.topics[0] === commandTopic)).to.have.length(0);
        });
      });
    }

    for (const state of [balance, balances]) {
      it(`relayPayable rejects ${state === balance ? "one BALANCE" : "multiple BALANCE blocks"} through a pipeline`, async () => {
        const steps = encodeStepBlock(await cmd("relayPayable"), 0n, transport);
        await expectPipelineRevert("relayPayable", state, steps, "UnconsumedData");
      });
    }

    for (const count of [0, 1, 2, 16]) {
      it(`relayBalancePayable forwards all ${count} balances exactly once without changing their bytes`, async () => {
        const state = concat(...Array.from({ length: count }, (_, i) =>
          encodeBalanceBlock(i % 2 === 0 ? asset : liability, i === 0 ? 0n : ethers.MaxUint256 - BigInt(i)),
        ));
        const [output, credit] = await host.relayBalancePayable.staticCall(...ctx({ state, input }), { value: 3n });
        expect(output).to.equal("0x");
        expect(credit).to.equal(3n);
        const tx = await callAs(0, "relayBalancePayable", ctx({ state, input }), { value: 3n });
        await expect(tx).to.emit(host, "RelayCalled")
          .withArgs(portal, 0n, userAccount, encodeContextBlock(userAccount, state, continuation));
        const receipt = await tx.wait();
        const relayTopic = host.interface.getEvent("RelayCalled")!.topicHash;
        expect(receipt!.logs.filter((log) => log.topics[0] === relayTopic)).to.have.length(1);
      });
    }
  });

  describe("recoverPayable", () => {
    it("discovers recoverPayable as a payable recovery command", async () => {
      const deployment = host.deploymentTransaction();
      expect(deployment).to.not.equal(null);

      await expect(deployment!).to.emit(host, "Endpoint")
        .withArgs(
          await host.host(),
          await cmd("recoverPayable"),
          endpointDescriptor({ input: Keys.Recover, inputHint: 256, funded: true }),
        );
      await expect(deployment!).to.emit(host, "Annotation")
        .withArgs(await cmd("recoverPayable"), encodeLabelBlock(ethers.ZeroHash, "recoverPayable"));
    });

    it("passes full recovery resources and the shared value budget to the hook", async () => {
      const key = ethers.zeroPadValue("0xbeef", 32);
      const handler = 99n;
      const resources = (7n << 128n) | 13n;
      const step = encodeStepBlock(0n, 0n, "0x1234");
      const witness = encodeContextBlock(userAccount, "0x", step);
      const input = encodeRecoverBlock(handler, resources, key, witness);

      const [result, transactions] = await host.recoverPayable.staticCall(...ctx({ input: input }), { value: 13n });
      expect(result).to.equal("0x");
      expect(transactions).to.equal(0n);

      const tx = await callAs(0, "recoverPayable", ctx({ input: input }), { value: 13n });
      await expect(tx).to.emit(host, "RecoverCalled")
        .withArgs(handler, resources, key, witness, 13n);
    });

    it("returns unspent command value after recovery as credit", async () => {
      const key = ethers.zeroPadValue("0xcafe", 32);
      const witness = encodeContextBlock(userAccount, "0x", "0x");
      const input = encodeRecoverBlock(0n, 0n, key, witness);

      const [state, transactions] = await host.recoverPayable.staticCall(...ctx({ input: input }), { value: 1n });
      expect(state).to.equal("0x");
      expect(transactions).to.equal(1n);
    });
  });

  describe("pipeline", () => {
    for (const [method, hook] of [
      ["debitAccount", "DebitFromCalled"],
      ["creditAccount", "CreditToCalled"],
      ["settle", "SettleCalled"],
    ]) {
      it(`accepts an empty local ${method} batch without calling its hook`, async () => {
        const steps = encodeStepBlock(await cmd(method), 0n, "0x");
        const receipt = await (await callAs(0, "testPipe", userAccount, "0x", steps)).wait();
        expect(receipt.logs.map((log: any) => log.topics[0]))
          .not.to.include(host.interface.getEvent(hook)!.topicHash);
      });

      it(`returns assigned value for an empty local ${method} batch`, async () => {
        const steps = encodeStepBlock(await cmd(method), 1n, "0x");
        await expect(callAs(0, "testPipe", userAccount, "0x", steps, { value: 1n }))
          .to.emit(host, "CreditToCalled").withArgs(userAccount, await utils.testToChain(), 1n, 1n);
      });

      it(`rejects a partial block in local ${method}`, async () => {
        const state = method === "debitAccount" ? "0x" : "0x01";
        const input = method === "debitAccount" ? "0x01" : "0x";
        const steps = encodeStepBlock(await cmd(method), 0n, input);
        await expect(callAs(0, "testPipe", userAccount, state, steps))
          .to.be.revertedWithCustomError(host, "InvalidBlock");
      });
    }

    it("still rejects undeclared sources for empty local debit and credit batches", async () => {
      await expect(callAs(0, "testPipe", userAccount, "0x01",
        encodeStepBlock(await cmd("debitAccount"), 0n, "0x")))
        .to.be.revertedWithCustomError(host, "UnexpectedState");
      await expect(callAs(0, "testPipe", userAccount, "0x",
        encodeStepBlock(await cmd("creditAccount"), 0n, "0x01")))
        .to.be.revertedWithCustomError(host, "UnexpectedInput");
    });

    it("executes cashout batches through optimized local execution", async () => {
      const chainAsset = await utils.testToChain();
      const state = concat(
        encodeBalanceBlock(chainAsset, 23n),
        encodeBalanceBlock(chainAsset, 29n),
      );
      const steps = encodeStepBlock(await cmd("cashout"), 0n, "0x");
      const tx = await callAs(0, "testPipe", userAccount, state, steps);
      await expect(tx).to.emit(host, "CashoutCalled").withArgs(userAccount, 23n);
      await expect(tx).to.emit(host, "CashoutCalled").withArgs(userAccount, 29n);
    });

    it("debits stored native value into state before cashing it out", async () => {
      const chainAsset = await utils.testToChain();
      const amount = 31n;
      const steps = concat(
        encodeStepBlock(
          await cmd("debitAccount"),
          0n,
          encodeAmountBlock(chainAsset, amount),
        ),
        encodeStepBlock(await cmd("cashout"), 0n, "0x"),
      );

      const tx = await callAs(0, "testPipe", userAccount, "0x", steps);
      await expect(tx).to.emit(host, "DebitFromCalled")
        .withArgs(userAccount, chainAsset, amount, amount);
      await expect(tx).to.emit(host, "CashoutCalled")
        .withArgs(userAccount, amount);
    });

    it("returns step value but rejects input for local cashout", async () => {
      const command = await cmd("cashout");
      const chainAsset = await utils.testToChain();
      const state = encodeBalanceBlock(chainAsset, 1n);
      const valued = encodeStepBlock(command, 1n, "0x");
      await expect(callAs(0, "testPipe", userAccount, state, valued, { value: 1n }))
        .to.emit(host, "CreditToCalled").withArgs(userAccount, chainAsset, 1n, 1n);

      const step = encodeStepBlock(command, 0n, encodeBalanceBlock(chainAsset, 1n));
      await expect(callAs(0, "testPipe", userAccount, state, step))
        .to.be.revertedWithCustomError(host, "UnexpectedInput");
    });

    it("rejects non-chain-asset state in optimized local cashout", async () => {
      const state = encodeBalanceBlock(ethers.ZeroHash, 1n);
      const step = encodeStepBlock(await cmd("cashout"), 0n, "0x");
      await expect(callAs(0, "testPipe", userAccount, state, step))
        .to.be.revertedWithCustomError(host, "InvalidAsset");
    });

    it("bootstraps balance and makes its budget available to a later step", async () => {
      const asset = ethers.zeroPadValue("0xa0", 32);
      const chainAsset = await utils.testToChain();
      const amount = 17n;
      const input = concat(
        encodeStepBlock(await cmd("bootstrap"), 0n, encodeBootstrapBlock(asset, 9n, amount)),
        encodeStepBlock(await remoteCmd("noop"), amount, "0x"),
        encodeStepBlock(await cmd("creditAccount"), 0n, "0x"),
      );

      await (await getSigner(0)).sendTransaction({ to: await host.getAddress(), value: amount });
      const tx = await callAs(0, "testPipe", userAccount, "0x", input);
      await expect(tx).to.emit(host, "DebitFromCalled")
        .withArgs(userAccount, asset, 9n, 9n);
      await expect(tx).to.emit(host, "DebitFromCalled")
        .withArgs(userAccount, chainAsset, amount, amount);
    });

    it("uses assigned value before debiting a chain-asset balance remainder", async () => {
      const chainAsset = await utils.testToChain();
      const input = concat(
        encodeStepBlock(
          await cmd("bootstrap"),
          4n,
          encodeBootstrapBlock(chainAsset, 7n, 0n),
        ),
        encodeStepBlock(await cmd("creditAccount"), 0n, "0x"),
      );

      const tx = await callAs(0, "testPipe", userAccount, "0x", input, { value: 4n });
      await expect(tx).to.emit(host, "DebitFromCalled")
        .withArgs(userAccount, chainAsset, 3n, 3n);
      await expect(tx).to.emit(host, "CreditToCalled")
        .withArgs(userAccount, chainAsset, 7n, 7n);
    });

    it("merges a chain-asset balance remainder and budget into one debit", async () => {
      const chainAsset = await utils.testToChain();
      const input = concat(
        encodeStepBlock(
          await cmd("bootstrap"),
          4n,
          encodeBootstrapBlock(chainAsset, 7n, 5n),
        ),
        encodeStepBlock(await cmd("creditAccount"), 0n, "0x"),
      );

      const tx = await callAs(0, "testPipe", userAccount, "0x", input, { value: 4n });
      const receipt = await tx.wait();
      const debits = receipt?.logs.filter((log: any) => {
        try {
          return host.interface.parseLog(log)?.name === "DebitFromCalled";
        } catch {
          return false;
        }
      });

      expect(debits).to.have.length(1);
      await expect(tx).to.emit(host, "DebitFromCalled")
        .withArgs(userAccount, chainAsset, 8n, 8n);
    });

    it("returns native value left after bootstrapping a chain-asset balance", async () => {
      const chainAsset = await utils.testToChain();
      const input = concat(
        encodeStepBlock(
          await cmd("bootstrap"),
          5n,
          encodeBootstrapBlock(chainAsset, 3n, 0n),
        ),
        encodeStepBlock(await cmd("creditAccount"), 0n, "0x"),
      );

      const tx = await callAs(0, "testPipe", userAccount, "0x", input, { value: 5n });
      const receipt = await tx.wait();
      const debits = receipt?.logs.filter((log: any) => {
        try {
          return host.interface.parseLog(log)?.name === "DebitFromCalled";
        } catch {
          return false;
        }
      });
      expect(debits).to.be.empty;
      await expect(tx).to.emit(host, "CreditToCalled")
        .withArgs(userAccount, chainAsset, 3n, 3n);
      await expect(tx).to.emit(host, "CreditToCalled")
        .withArgs(userAccount, chainAsset, 2n, 2n);
    });

    it("bootstraps batches through optimized local execution", async () => {
      const command = await cmd("bootstrap");
      const chainAsset = await utils.testToChain();
      const firstAsset = ethers.zeroPadValue("0xa2", 32);
      const secondAsset = ethers.zeroPadValue("0xa3", 32);
      const bootstrapInput = concat(
        encodeBootstrapBlock(firstAsset, 1n, 2n),
        encodeBootstrapBlock(secondAsset, 3n, 4n),
      );
      const steps = concat(
        encodeStepBlock(command, 0n, bootstrapInput),
        encodeStepBlock(await cmd("creditAccount"), 0n, "0x"),
      );
      const tx = await callAs(0, "testPipe", userAccount, "0x", steps);
      await expect(tx).to.emit(host, "DebitFromCalled")
        .withArgs(userAccount, firstAsset, 1n, 1n);
      await expect(tx).to.emit(host, "DebitFromCalled")
        .withArgs(userAccount, chainAsset, 2n, 2n);
      await expect(tx).to.emit(host, "DebitFromCalled")
        .withArgs(userAccount, secondAsset, 3n, 3n);
      await expect(tx).to.emit(host, "DebitFromCalled")
        .withArgs(userAccount, chainAsset, 4n, 4n);
    });

    it("requires bootstrap to start with empty pipeline state", async () => {
      const asset = ethers.zeroPadValue("0xa0", 32);
      const state = encodeBalanceBlock(asset, 1n);
      const steps = encodeStepBlock(
        await cmd("bootstrap"),
        0n,
        encodeBootstrapBlock(asset, 2n, 3n),
      );

      await expect(callAs(0, "testPipe", userAccount, state, steps))
        .to.be.revertedWithCustomError(host, "UnexpectedState");
    });

    it("executes local debit and credit commands against threaded state", async () => {
      const asset = ethers.zeroPadValue("0xa1", 32);
      const amount = 42n;
      const input = concat(
        encodeStepBlock(await cmd("debitAccount"), 0n, encodeAmountBlock(asset, amount)),
        encodeStepBlock(await cmd("creditAccount"), 0n, "0x"),
      );

      const tx = await callAs(0, "testPipe", userAccount, "0x", input);

      await expect(tx)
        .to.emit(host, "DebitFromCalled")
        .withArgs(userAccount, asset, amount, amount);
      await expect(tx)
        .to.emit(host, "CreditToCalled")
        .withArgs(userAccount, asset, amount, amount);
    });

    it("calls an unhandled local command through its normal entrypoint", async () => {
      const asset = ethers.zeroPadValue("0xa4", 32);
      const amount = 43n;
      const input = concat(
        encodeStepBlock(await cmd("deposit"), 0n, encodeAmountBlock(asset, amount)),
        encodeStepBlock(await cmd("creditAccount"), 0n, "0x"),
      );

      const tx = await callAs(0, "testPipe", userAccount, "0x", input);

      await expect(tx)
        .to.emit(host, "DepositCalled")
        .withArgs(userAccount, asset, amount);
      await expect(tx)
        .to.emit(host, "CreditToCalled")
        .withArgs(userAccount, asset, amount, amount);
    });

    it("executes local settlement against memory-backed position state", async () => {
      const asset = ethers.zeroPadValue("0xb1", 32);
      const liability = ethers.zeroPadValue("0xb2", 32);
      const amount = 75n;
      const debt = 25n;
      const state = encodePositionBlock(asset, amount, liability, debt, userAccount);
      const input = encodeStepBlock(await cmd("settle"), 0n, "0x");

      const tx = await callAs(0, "testPipe", userAccount, state, input);

      await expect(tx)
        .to.emit(host, "SettleCalled")
        .withArgs(userAccount, asset, amount, liability, debt);
    });

    it("settles liability-only positions from memory", async () => {
      const liability = ethers.zeroPadValue("0xb3", 32);
      const debt = 25n;
      const state = encodePositionBlock(ethers.ZeroHash, 0n, liability, debt, userAccount);
      const input = encodeStepBlock(await cmd("settle"), 0n, "0x");

      const tx = await callAs(0, "testPipe", userAccount, state, input);

      await expect(tx)
        .to.emit(host, "SettleCalled")
        .withArgs(userAccount, ethers.ZeroHash, 0n, liability, debt);
    });

    it("rejects input for state-only local commands", async () => {
      const asset = ethers.zeroPadValue("0xb4", 32);
      const liability = ethers.zeroPadValue("0xb5", 32);
      const input = encodeAmountBlock(asset, 1n);
      const cases = [
        { command: "creditAccount", state: encodeBalanceBlock(asset, 1n) },
      ];

      for (const testCase of cases) {
        await expect(
          callAs(
            0,
            "testPipe",
            userAccount,
            testCase.state,
            encodeStepBlock(await cmd(testCase.command), 0n, input),
          ),
        ).to.be.revertedWithCustomError(host, "UnexpectedInput");
      }
    });

    it("processes batched fixed-stride streams in execute adapters", async () => {
      const asset = ethers.zeroPadValue("0xb4", 32);
      const liability = ethers.zeroPadValue("0xb5", 32);

      const debitCreditTx = await callAs(
        0,
        "testPipe",
        userAccount,
        "0x",
        concat(
          encodeStepBlock(
            await cmd("debitAccount"),
            0n,
            concat(encodeAmountBlock(asset, 1n), encodeAmountBlock(asset, 2n)),
          ),
          encodeStepBlock(await cmd("creditAccount"), 0n, "0x"),
        ),
      );
      await expect(debitCreditTx).to.emit(host, "DebitFromCalled").withArgs(userAccount, asset, 2n, 2n);
      await expect(debitCreditTx).to.emit(host, "CreditToCalled").withArgs(userAccount, asset, 2n, 2n);

      const settleTx = await callAs(
        0,
        "testPipe",
        userAccount,
        concat(
          encodePositionBlock(asset, 3n, liability, 4n, userAccount),
          encodePositionBlock(asset, 5n, liability, 6n, userAccount),
        ),
        encodeStepBlock(await cmd("settle"), 0n, "0x"),
      );
      await expect(settleTx)
        .to.emit(host, "SettleCalled")
        .withArgs(userAccount, asset, 5n, liability, 6n);

      const repayTx = await callAs(
        0,
        "testPipe",
        userAccount,
        concat(encodePositionBlock(ethers.ZeroHash, 0n, liability, 7n, userAccount), encodePositionBlock(ethers.ZeroHash, 0n, liability, 8n, userAccount)),
        encodeStepBlock(await cmd("settle"), 0n, "0x"),
      );
      await expect(repayTx)
        .to.emit(host, "SettleCalled")
        .withArgs(userAccount, ethers.ZeroHash, 0n, liability, 8n);
    });

    it("rejects malformed fixed-stride memory state in execute adapters", async () => {
      const asset = ethers.zeroPadValue("0xb6", 32);
      const liability = ethers.zeroPadValue("0xb7", 32);
      const position = encodePositionBlock(asset, 1n, liability, 2n);
      const cases = [
        { command: "creditAccount", state: encodeAmountBlock(asset, 1n) },
        { command: "settle", state: ethers.dataSlice(position, 0, ethers.dataLength(position) - 1) },
        { command: "settle", state: encodeBalanceBlock(liability, 1n) },
      ];

      for (const testCase of cases) {
        await expect(
          callAs(
            0,
            "testPipe",
            userAccount,
            testCase.state,
            encodeStepBlock(await cmd(testCase.command), 0n, "0x"),
          ),
        ).to.be.revertedWithCustomError(host, "InvalidBlock");
      }
    });

    it("rejects malformed fixed-stride calldata input in the internal debit command", async () => {
      const asset = ethers.zeroPadValue("0xb8", 32);
      const amount = encodeAmountBlock(asset, 1n);
      const inputs = [
        encodeBalanceBlock(asset, 1n),
        ethers.dataSlice(amount, 0, ethers.dataLength(amount) - 1),
      ];

      for (const input of inputs) {
        await expect(
          callAs(
            0,
            "testPipe",
            userAccount,
            "0x",
            encodeStepBlock(await cmd("debitAccount"), 0n, input),
          ),
        ).to.be.revertedWithCustomError(host, "InvalidBlock");
      }
    });

    it("returns unused value from populated local commands exactly once", async () => {
      const asset = ethers.zeroPadValue("0xc1", 32);
      const liability = ethers.zeroPadValue("0xc2", 32);
      const cases = [
        {
          command: "debitAccount",
          state: "0x",
          input: encodeAmountBlock(asset, 1n),
        },
        {
          command: "creditAccount",
          state: encodeBalanceBlock(asset, 1n),
          input: "0x",
        },
        {
          command: "settle",
          state: encodePositionBlock(asset, 1n, liability, 1n, userAccount),
          input: "0x",
        },
        {
          command: "settle",
          state: encodePositionBlock(ethers.ZeroHash, 0n, liability, 1n, userAccount),
          input: "0x",
        },
      ];

      for (const testCase of cases) {
        let steps = encodeStepBlock(
          await cmd(testCase.command),
          1n,
          testCase.input,
        );
        if (testCase.command === "debitAccount") {
          steps = concat(steps, encodeStepBlock(await cmd("creditAccount"), 1n, "0x"));
        }
        await expect(
          callAs(0, "testPipe", userAccount, testCase.state, steps, { value: 1n }),
        ).to.emit(host, "CreditToCalled").withArgs(userAccount, await utils.testToChain(), 1n, 1n);
      }
    });

    it("preserves assigned value across empty adapters for a later funded step", async () => {
      const steps = concat(
        ...await Promise.all(["debitAccount", "creditAccount", "settle", "cashout"]
          .map(async method => encodeStepBlock(await cmd(method), 7n, "0x"))),
        encodeStepBlock(await remoteCmd("noop"), 7n, "0x"),
      );
      const tx = await callAs(0, "testPipe", userAccount, "0x", steps, { value: 7n });
      await expect(tx).to.emit(remote, "CommandCalled")
        .withArgs(remote.interface.getFunction("noop")!.selector, 7n);
      const receipt = await tx.wait();
      expect(receipt.logs.map((log: any) => log.topics[0]))
        .not.to.include(host.interface.getEvent("CreditToCalled")!.topicHash);
      await expect(callAs(0, "testPipe", userAccount, "0x", steps, { value: 6n }))
        .to.be.revertedWithCustomError(host, "InsufficientValue");
    });

    it("executes trusted remote STEP commands directly", async () => {
      const input = encodeStepBlock(await remoteCmd("noop"), 0n, "0x");
      const tx = await callAs(0, "testPipe", userAccount, "0x", input);
      await expect(tx).to.emit(remote, "CommandCalled")
        .withArgs(remote.interface.getFunction("noop")!.selector, 0n);
    });

    it("threads state through multiple steps", async () => {
      const command = await remoteCmd("noop");
      const input = concat(
        encodeStepBlock(command, 0n, "0x"),
        encodeStepBlock(command, 0n, "0x")
      );
      const tx = await callAs(0, "testPipe", userAccount, "0x", input);
      const receipt = await tx.wait();
      const calls = receipt!.logs.filter((log) => {
        try {
          return remote.interface.parseLog(log)?.name === "CommandCalled";
        } catch {
          return false;
        }
      });
      expect(calls).to.have.length(2);
    });

    it("passes each remote command selector and EVM value to its target", async () => {
      const first = await remoteCmd("first");
      const second = await remoteCmd("second");
      const input = concat(
        encodeStepBlock(first, 7n, "0x1234"),
        encodeStepBlock(second, 9n, "0xabcd")
      );
      const tx = await callAs(0, "testPipe", userAccount, "0x", input, { value: 16n });
      await expect(tx).to.emit(remote, "CommandCalled")
        .withArgs(remote.interface.getFunction("first")!.selector, 7n);
      await expect(tx).to.emit(remote, "CommandCalled")
        .withArgs(remote.interface.getFunction("second")!.selector, 9n);
    });

    it("encodes step values wider than uint128", async () => {
      expect(() => encodeStepBlock(11n, 1n << 128n, "0x1234"))
        .not.to.throw();
    });

    it("hands ordinary input and the remaining steps to a handoff command", async () => {
      const portal = (0x03020100n << 224n) | 31337n;
      const resources = 9n;
      const state = encodeBalanceBlock(ethers.zeroPadValue("0x80", 32), 12n);
      const continuation = encodeStepBlock(await remoteCmd("noop"), 7n, "0x1234");
      const relayInput = encodeRelayInputBlock(portal, resources);
      const steps = concat(
        encodeStepBlock(
          await cmd("relayBalancePayable"),
          0n,
          relayInput,
        ),
        continuation,
      );

      const tx = await callAs(0, "testPipe", userAccount, state, steps, { value: 7n });
      await expect(tx).to.emit(host, "RelayCalled")
        .withArgs(portal, resources, userAccount, encodeContextBlock(userAccount, state, continuation));
      const receipt = await tx.wait();
      const calls = receipt!.logs.filter((log) => {
        try {
          return remote.interface.parseLog(log)?.name === "CommandCalled";
        } catch {
          return false;
        }
      });
      expect(calls).to.have.length(0);
    });

    it("settles trusted returned value once after the pipeline closes", async () => {
      const input = encodeStepBlock(await remoteCmd("credit"), 0n, "0x1234");
      const chainAsset = await utils.testToChain();

      const tx = await callAs(0, "testPipe", userAccount, "0x", input);

      await expect(tx)
        .to.emit(host, "CreditToCalled")
        .withArgs(userAccount, chainAsset, 123n, 123n);
    });

    it("makes command-returned value available to later steps", async () => {
      const chainAsset = await utils.testToChain();
      const creditCommand = await remoteCmd("credit");
      const spendCommand = await remoteCmd("noop");
      const input = concat(
        encodeStepBlock(creditCommand, 0n, "0x"),
        encodeStepBlock(spendCommand, 100n, "0x"),
      );

      await (await getSigner(0)).sendTransaction({ to: await host.getAddress(), value: 100n });
      const tx = await callAs(0, "testPipe", userAccount, "0x", input);
      await expect(tx).to.emit(remote, "CommandCalled")
        .withArgs(remote.interface.getFunction("credit")!.selector, 0n);
      await expect(tx).to.emit(remote, "CommandCalled")
        .withArgs(remote.interface.getFunction("noop")!.selector, 100n);
      await expect(tx).to.emit(host, "CreditToCalled")
        .withArgs(userAccount, chainAsset, 23n, 23n);
    });

    it("settles the final pipeline budget after the pipeline closes", async () => {
      const input = encodeStepBlock(await remoteCmd("noop"), 0n, "0x");
      const chainAsset = await utils.testToChain();

      const tx = await callAs(0, "testPipe", userAccount, "0x", input, { value: 5n });

      await expect(tx)
        .to.emit(host, "CreditToCalled")
        .withArgs(userAccount, chainAsset, 5n, 5n);
    });

    it("reverts UnexpectedState when final threaded state is non-empty", async () => {
      const state = encodeBalanceBlock(
        ethers.zeroPadValue("0x99", 32),
        123n
      );
      const input = encodeStepBlock(await remoteCmd("noop"), 0n, "0x");
      await expect(host.testPipe.staticCall(userAccount, state, input))
        .to.be.revertedWithCustomError(host, "UnexpectedState");
    });

    it("accepts an empty STEP batch", async () => {
      await host.testPipe.staticCall(userAccount, "0x", "0x");
    });

    it("rejects a STEP whose command ID is not a command node", async () => {
      const input = encodeStepBlock(0n, 0n, "0x");
      await expect(host.testPipe.staticCall(userAccount, "0x", input))
        .to.be.revertedWithCustomError(host, "InvalidId");
    });

    it("rejects an untrusted remote command", async () => {
      const command = await commandId("noop(bytes)", utils);
      const input = encodeStepBlock(command, 0n, "0x");
      await expect(host.testPipe.staticCall(userAccount, "0x", input))
        .to.be.revertedWithCustomError(host, "AccessDenied");
    });

    it("rejects revoked handled and delegated local commands", async () => {
      for (const name of ["cashout", "deposit"] as const) {
        const command = await cmd(name);
        const trustInput = encodeContextBlock(
          adminAccount,
          "0x",
          encodeNodeBlock(command),
        );

        await host.unauthorize(trustInput);
        try {
          const input = encodeStepBlock(command, 0n, "0x");
          await expect(host.testPipe.staticCall(userAccount, "0x", input))
            .to.be.revertedWithCustomError(host, "AccessDenied");
        } finally {
          await host.authorize(trustInput);
        }
      }
    });

    it("rejects a non-STEP block trailing the STEP stream", async () => {
      const input = concat(
        encodeStepBlock(await remoteCmd("noop"), 0n, "0x"),
        encodeAmountBlock(ethers.ZeroHash, 1n),
      );

      await expect(callAs(0, "testPipe", userAccount, "0x", input))
        .to.be.revertedWithCustomError(host, "InvalidBlock");
    });

    it("rejects a STEP block extending beyond the stream boundary", async () => {
      const complete = ethers.getBytes(encodeStepBlock(0n, 0n, "0x"));
      const input = ethers.hexlify(complete.slice(0, -1));

      await expect(callAs(0, "testPipe", userAccount, "0x", input))
        .to.be.revertedWithCustomError(host, "OutOfBounds");
    });


    it("tracks ETH value budget â€” reverts InsufficientValue when step requests too much", async () => {
      const largeValue = ethers.parseEther("1000");
      const input = encodeStepBlock(await remoteCmd("noop"), largeValue, "0x");
      await expect(
        (host.connect(await getSigner(0)) as any).testPipe(userAccount, "0x", input, { value: 0n })
      ).to.be.revertedWithCustomError(host, "InsufficientValue");
    });
  });
});
