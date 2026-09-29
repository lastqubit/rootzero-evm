import { expect } from "chai";
import { ethers } from "ethers";
import { deploy, getSigner, hostId } from "./helpers/setup.js";
import { encodeAccountBlock, encodeContextBlock, encodeNodeBlock, encodeUserAccount } from "./helpers/blocks.js";
import "./helpers/matchers.js";

describe("Access state events", () => {
  for (const kind of ["Node", "Guardian"] as const) {
    it(`${kind} publishes its ABI and records actions with resulting state on repeated operations`, async () => {
      const commander = await (await getSigner()).getAddress();
      const host = await deploy("TestHost", await hostId(commander));
      const account = await host.getAdminAccount();
      const target = await (await getSigner(4)).getAddress();
      const subject = kind === "Node" ? await hostId(target) : encodeUserAccount(target);
      const input = kind === "Node" ? encodeNodeBlock(subject as bigint) : encodeAccountBlock(subject as string);
      const signature = kind === "Node"
        ? "event Node(uint indexed host, uint node, uint codes)"
        : "event Guardian(uint indexed host, bytes32 account, uint codes)";
      await expect(host.deploymentTransaction()).to.emit(host, "EventAbi").withArgs(signature);
      const decoder = new ethers.Interface([signature]);
      const id = await host.host();
      for (const active of [true, true, false, false]) {
        const method = kind === "Node" ? (active ? "authorize" : "unauthorize") : (active ? "appoint" : "dismiss");
        const action = kind === "Node" ? (active ? 16n : 17n) : (active ? 18n : 19n);
        const codes = action | ((active ? 0xa0000001n : 0xa0000000n) << 32n);
        const receipt = await (await host[method](encodeContextBlock(account, "0x", input))).wait();
        const logs = receipt.logs.filter((log: any) => log.topics[0] === decoder.getEvent(kind)!.topicHash);
        expect(logs).to.have.length(1);
        expect(logs[0].topics).to.deep.equal([decoder.getEvent(kind)!.topicHash, ethers.toBeHex(id, 32)]);
        expect(ethers.dataLength(logs[0].data)).to.equal(64);
        expect(Array.from(decoder.parseLog(logs[0])!.args)).to.deep.equal([id, subject, codes]);
        expect(kind === "Node" ? await host.isAuthorized(subject) : await host.isGuardianAddress(target)).to.equal(active);
      }
    });
  }
});

describe("Asset events", () => {
  const preimageSignature = "event AssetPreimage(bytes32 indexed asset, bytes preimage)";
  const assetSignature = "event Asset(uint indexed host, bytes32 asset, uint codes)";

  it("publishes both renamed event ABIs through the public event exports", async () => {
    const emitter = await deploy("TestAssetEvents");
    const receipt = await emitter.deploymentTransaction()!.wait();
    const published = receipt.logs.map((log: any) => emitter.interface.parseLog(log))
      .filter((log: any) => log?.name === "EventAbi").map((log: any) => log.args.abi);
    expect(published).to.have.members([preimageSignature, assetSignature]);
    expect(published).to.have.length(2);
  });

  it("indexes the asset ID directly and preserves the complete preimage without a host field", async () => {
    const emitter = await deploy("TestAssetEvents");
    const asset = ethers.toBeHex(123n, 32);
    const decoder = new ethers.Interface([preimageSignature]);
    for (const preimage of ["0x", "0x010301", "0x" + "ab".repeat(65)]) {
      const receipt = await (await emitter.emitPreimage(asset, preimage)).wait();
      expect(receipt.logs).to.have.length(1);
      const log = receipt.logs[0];
      expect(log.topics).to.deep.equal([decoder.getEvent("AssetPreimage")!.topicHash, asset]);
      expect(Array.from(decoder.parseLog(log)!.args)).to.deep.equal([asset, preimage]);
    }
  });

  it("records action and state codes while indexing the host", async () => {
    const emitter = await deploy("TestAssetEvents");
    const asset = ethers.toBeHex(123n, 32);
    const host = 456n;
    const decoder = new ethers.Interface([assetSignature]);
    for (const codes of [20n | (0xa0000001n << 32n), 21n | (0xa0000000n << 32n),
      1n | (0xa0000000n << 32n), 2n | (0xa0000001n << 32n),
      0x1fffffffn | (0xa0000001n << 32n) | Array.from({ length: 6 }, (_, i) => 1n << BigInt((i + 2) * 32)).reduce((a, b) => a | b, 0n)] as const) {
      const receipt = await (await emitter.emitAsset(host, asset, codes)).wait();
      expect(receipt.logs).to.have.length(1);
      const log = receipt.logs[0];
      expect(log.topics).to.deep.equal([decoder.getEvent("Asset")!.topicHash, ethers.toBeHex(host, 32)]);
      expect(ethers.dataLength(log.data)).to.equal(64);
      expect(Array.from(decoder.parseLog(log)!.args)).to.deep.equal([host, asset, codes]);
    }
  });
});

describe("Route event", () => {
  it("publishes its ABI and preserves each action and resulting state code", async () => {
    const emitter = await deploy("TestRouteEvent");
    const signature = "event Route(uint indexed host, uint portal, uint codes)";
    await expect(emitter.deploymentTransaction()).to.emit(emitter, "EventAbi").withArgs(signature);
    const decoder = new ethers.Interface([signature]);
    const host = 123n;
    const portal = 456n;
    for (const [action, state] of [
      [4n, 0xa0000001n], [4n, 0xa0000001n], [7n, 0xa0000000n],
      [6n, 0xa0000001n], [5n, 0xa0000000n], [0x1fffffffn, 0xa0000001n],
    ] as const) {
      const codes = action | (state << 32n);
      const receipt = await (await emitter.emitRoute(host, portal, codes)).wait();
      expect(receipt.logs).to.have.length(1);
      const log = receipt.logs[0];
      expect(log.topics).to.deep.equal([decoder.getEvent("Route")!.topicHash, ethers.toBeHex(host, 32)]);
      expect(ethers.dataLength(log.data)).to.equal(64);
      expect(Array.from(decoder.parseLog(log)!.args)).to.deep.equal([host, portal, codes]);
    }
  });
});

describe("Activity event", () => {
  it("records spend, receive, lock, and unlock flows through explicit effect codes", async () => {
    const emitter = await deploy("TestActivityEvent");
    const account = ethers.toBeHex(1, 32);
    const asset = ethers.toBeHex(2, 32);
    for (const effect of [0x80000000n, 0x80000001n, 0x80000002n, 0x80000003n]) {
      for (const amount of [0n, 100n, ethers.MaxUint256]) {
        await expect(emitter.emitActivity(account, asset, amount, effect))
          .to.emit(emitter, "Activity").withArgs(account, asset, amount, effect);
      }
    }
  });

  it("publishes its ABI alongside annotations and indexes the account", async () => {
    const emitter = await deploy("TestActivityEvent");
    const signature = "event Activity(bytes32 indexed account, bytes32 subject, uint value, uint codes)";
    await expect(emitter.deploymentTransaction())
      .to.emit(emitter, "EventAbi").withArgs(signature);

    const account = ethers.zeroPadValue("0x01", 32);
    const subject = ethers.toBeHex(ethers.MaxUint256, 32);
    const decoder = new ethers.Interface([signature]);
    for (const removed of ["Action", "Spent", "Received", "Locked", "Unlocked"]) {
      expect(emitter.interface.getEvent(removed)).to.equal(null);
    }
    const pack = (ids: bigint[]) => ids.reduce((word, id, i) => word | (id << BigInt(32 * i)), 0n);
    for (const [codes, value] of [
      [0n, 0n],
      [34n, 0n],
      [0x80000002n, 0n],
      [pack([80n, 0x80000000n, 0x80000001n]), 1n],
      [pack([1n, 0x7fffffffn, 0x80000000n, 4n, 0x80000001n, 6n, 7n, 0xffffffffn]), ethers.MaxUint256],
      [ethers.MaxUint256, 0n],
    ]) {
      const receipt = await (await emitter.emitActivity(account, subject, value, codes)).wait();
      expect(receipt.logs).to.have.length(1);
      const log = receipt.logs[0];
      expect(log.topics).to.deep.equal([decoder.getEvent("Activity")!.topicHash, account]);
      expect(ethers.dataLength(log.data)).to.equal(96);
      expect(Array.from(decoder.parseLog(log)!.args)).to.deep.equal([account, subject, value, codes]);
    }
  });

  it("accepts single constants directly and packs multiple IDs through public exports", async () => {
    const emitter = await deploy("TestActivityEvent");
    const account = ethers.zeroPadValue("0x01", 32);
    const receipt = await (await emitter.emitExamples(account)).wait();
    const activities = receipt.logs.map((log: any) => Array.from(emitter.interface.parseLog(log)!.args));
    expect(activities).to.deep.equal([
      [account, 0n, 0n],
      [account, 34n, 0n],
      [account, 0x80000002n, 0n],
      [account, 0xa0000001n, 0n],
      [account, 0xa0000000n, 0n],
      [account, 4n | (0xa0000001n << 32n), 0n],
      [account, 5n | (0xa0000000n << 32n), 0n],
      [account, 6n | (0xa0000001n << 32n), 0n],
      [account, 7n | (0xa0000000n << 32n), 0n],
      [account, 16n | (0xa0000001n << 32n), 0n],
      [account, 17n | (0xa0000000n << 32n), 0n],
      [account, 18n | (0xa0000001n << 32n), 0n],
      [account, 19n | (0xa0000000n << 32n), 0n],
      [account, 20n | (0xa0000001n << 32n), 0n],
      [account, 21n | (0xa0000000n << 32n), 0n],
      [account, 80n | (81n << 32n) | (0x80000000n << 64n) | (0x80000001n << 96n) |
        (0x80000002n << 128n) | (0x80000003n << 160n) |
        (0xa0000001n << 192n) | (0xa0000000n << 224n), 1n],
    ].map(([account, codes, value]) => [account, ethers.ZeroHash, value, codes]));
  });
});

describe("Positioned Event", () => {
  it("publishes its ABI and emits the resulting position with its action", async () => {
    const positioned = await deploy("TestPositionedEvent");
    const receipt = await positioned.deploymentTransaction()!.wait();
    const abi = receipt!.logs
      .map((log: any) => {
        try {
          return positioned.interface.parseLog(log);
        } catch {
          return null;
        }
      })
      .find((log: any) => log?.name === "EventAbi");

    expect(abi!.args.abi).to.equal(
      "event Positioned(bytes32 indexed account, bytes32 asset, uint amount, bytes32 liability, uint debt, bytes32 counterparty, uint codes)",
    );

    const account = ethers.zeroPadValue("0x01", 32);
    const asset = ethers.zeroPadValue("0x02", 32);
    const liability = ethers.zeroPadValue("0x03", 32);
    const counterparty = ethers.zeroPadValue("0x04", 32);
    await expect(positioned.emitPositioned(account, asset, 100n, liability, 25n, counterparty, 80n | (0x80000001n << 32n)))
      .to.emit(positioned, "Positioned")
      .withArgs(account, asset, 100n, liability, 25n, counterparty, 80n | (0x80000001n << 32n));
  });
});

describe("Balance events", () => {
  const signatures = [
    "event Balance(bytes32 indexed account, bytes32 asset, uint balance)",
  ];

  for (const contract of ["TestBalanceEvents", "TestBalancesLedger"]) {
    it(`${contract} publishes the account balance event ABI without access`, async () => {
      const emitter = await deploy(contract);
      const receipt = await emitter.deploymentTransaction()!.wait();
      const published = receipt.logs
        .map((log: any) => emitter.interface.parseLog(log))
        .filter((log: any) => log?.name === "EventAbi")
        .map((log: any) => log.args.abi);
      expect(published).to.have.members(signatures);
      expect(published).to.have.length(1);
    });
  }

  for (const [index, name, method, owner] of [
    [0, "Balance", "emitBalance", ethers.zeroPadValue("0x21", 32)],
  ] as const) {
    for (const balance of [0n, 70n, ethers.MaxUint256]) {
      it(`${name} indexes its owner and encodes balance ${balance}`, async () => {
        const emitter = await deploy("TestBalanceEvents");
        const asset = ethers.zeroPadValue("0x11", 32);
        const receipt = await (await emitter[method](owner, asset, balance)).wait();
        const decoder = new ethers.Interface([signatures[index]!]);
        expect(receipt.logs).to.have.length(1);
        const log = receipt.logs[0];
        expect(log.topics).to.deep.equal([
          decoder.getEvent(name)!.topicHash,
          ethers.toBeHex(BigInt(owner), 32),
        ]);
        expect(ethers.dataLength(log.data)).to.equal(64);
        expect(Array.from(decoder.parseLog(log)!.args)).to.deep.equal([
          owner, asset, balance,
        ]);
      });
    }
  }
});

describe("Shared event codes", () => {
  const account = ethers.toBeHex(1, 32);
  const asset = ethers.toBeHex(2, 32);
  // Empty, single, mixed categories, duplicates, and all eight occupied slots.
  const cases = [0n, 80n, 80n | (0x80000001n << 32n),
    80n | (80n << 32n), Array.from({ length: 8 }, (_, i) => 1n << BigInt(i * 32))
      .reduce((codes, entry) => codes | entry, 0n)];
  for (const name of ["Activity", "Node", "Guardian"]) {
    it(`${name} publishes its codes ABI and preserves all slots without a context field`, async () => {
      const emitter = await deploy("TestEventCodes");
      const signature = name === "Node"
        ? "event Node(uint indexed host, uint node, uint codes)"
        : name === "Guardian"
          ? "event Guardian(uint indexed host, bytes32 account, uint codes)"
          : `event ${name}(bytes32 indexed account, bytes32 subject, uint value, uint codes)`;
      await expect(emitter.deploymentTransaction()).to.emit(emitter, "EventAbi").withArgs(signature);
      const decoder = new ethers.Interface([signature]);
      const stateEvent = name === "Node" || name === "Guardian";
      const eventCases = stateEvent ? [0xa0000000n, 16n | (0xa0000001n << 32n),
        (cases[4] & ((1n << 224n) - 1n)) | (0xa0000000n << 224n)] : cases;
      for (const codes of eventCases) {
        const args = name === "Node" ? [1n, 2n, codes]
          : name === "Guardian" ? [1n, account, codes]
          : [account, asset, ethers.MaxUint256, codes];
        const receipt = await (await emitter["emit" + name](...args)).wait();
        expect(receipt.logs).to.have.length(1);
        const log = receipt.logs[0];
        expect(log.topics).to.deep.equal([decoder.getEvent(name)!.topicHash, account]);
        expect(ethers.dataLength(log.data)).to.equal(stateEvent ? 64 : 96);
        const decoded = decoder.parseLog(log)!.args;
        expect(Array.from(decoded)).to.deep.equal(args);
        expect(decoded.codes).to.equal(codes);
      }
    });
  }
});
