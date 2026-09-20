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
        ? "event Node(uint indexed host, uint node, uint32 action, uint status)"
        : "event Guardian(uint indexed host, bytes32 account, uint32 action, uint status)";
      await expect(host.deploymentTransaction()).to.emit(host, "EventAbi").withArgs(signature);
      const decoder = new ethers.Interface([signature]);
      const id = await host.host();
      for (const active of [true, true, false, false]) {
        const method = kind === "Node" ? (active ? "authorize" : "unauthorize") : (active ? "appoint" : "dismiss");
        const action = kind === "Node" ? (active ? 16n : 17n) : (active ? 18n : 19n);
        const receipt = await (await host[method](encodeContextBlock(account, "0x", input))).wait();
        const logs = receipt.logs.filter((log: any) => log.topics[0] === decoder.getEvent(kind)!.topicHash);
        expect(logs).to.have.length(1);
        expect(logs[0].topics).to.deep.equal([decoder.getEvent(kind)!.topicHash, ethers.toBeHex(id, 32)]);
        expect(ethers.dataLength(logs[0].data)).to.equal(96);
        expect(Array.from(decoder.parseLog(logs[0])!.args)).to.deep.equal([id, subject, action, active ? 1n : 0n]);
        expect(kind === "Node" ? await host.isAuthorized(subject) : await host.isGuardianAddress(target)).to.equal(active);
      }
    });
  }
});

describe("Asset events", () => {
  const preimageSignature = "event AssetPreimage(bytes32 indexed asset, bytes preimage)";
  const assetSignature = "event Asset(uint indexed host, bytes32 asset, uint32 action, uint status)";

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

  it("records actions and full-width status while indexing the host", async () => {
    const emitter = await deploy("TestAssetEvents");
    const asset = ethers.toBeHex(123n, 32);
    const host = 456n;
    const decoder = new ethers.Interface([assetSignature]);
    for (const [action, status] of [[20n, 1n], [21n, 0n], [2n, 2n], [0xffffffffn, ethers.MaxUint256]] as const) {
      const receipt = await (await emitter.emitAsset(host, asset, action, status)).wait();
      expect(receipt.logs).to.have.length(1);
      const log = receipt.logs[0];
      expect(log.topics).to.deep.equal([decoder.getEvent("Asset")!.topicHash, ethers.toBeHex(host, 32)]);
      expect(ethers.dataLength(log.data)).to.equal(96);
      expect(Array.from(decoder.parseLog(log)!.args)).to.deep.equal([host, asset, action, status]);
    }
  });
});

describe("Route event", () => {
  it("publishes its ABI and preserves each action and resulting status", async () => {
    const emitter = await deploy("TestRouteEvent");
    const signature = "event Route(uint indexed host, uint portal, uint32 action, uint status)";
    await expect(emitter.deploymentTransaction()).to.emit(emitter, "EventAbi").withArgs(signature);
    const decoder = new ethers.Interface([signature]);
    const host = 123n;
    const portal = 456n;
    for (const [action, status] of [
      [4n, 1n], [4n, 1n], [7n, 0n], [6n, 1n], [5n, 0n], [2n, 2n], [0xffffffffn, ethers.MaxUint256],
    ] as const) {
      const receipt = await (await emitter.emitRoute(host, portal, action, status)).wait();
      expect(receipt.logs).to.have.length(1);
      const log = receipt.logs[0];
      expect(log.topics).to.deep.equal([decoder.getEvent("Route")!.topicHash, ethers.toBeHex(host, 32)]);
      expect(ethers.dataLength(log.data)).to.equal(96);
      expect(Array.from(decoder.parseLog(log)!.args)).to.deep.equal([host, portal, action, status]);
    }
  });
});

describe("Action event", () => {
  it("publishes its ABI alongside annotations and indexes the account", async () => {
    const emitter = await deploy("TestActionEvent");
    const signature = "event Action(bytes32 indexed account, uint32 action)";
    await expect(emitter.deploymentTransaction())
      .to.emit(emitter, "EventAbi").withArgs(signature);

    const account = ethers.zeroPadValue("0x01", 32);
    const receipt = await (await emitter.emitAction(account, 7)).wait();
    expect(receipt.logs).to.have.length(1);
    const log = receipt.logs[0];
    const decoder = new ethers.Interface([signature]);
    expect(log.topics).to.deep.equal([decoder.getEvent("Action")!.topicHash, account]);
    expect(ethers.dataLength(log.data)).to.equal(32);
    expect(Array.from(decoder.parseLog(log)!.args)).to.deep.equal([account, 7n]);
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
      "event Positioned(bytes32 indexed account, bytes32 asset, uint amount, bytes32 liability, uint debt, bytes32 counterparty, uint32 action)",
    );

    const account = ethers.zeroPadValue("0x01", 32);
    const asset = ethers.zeroPadValue("0x02", 32);
    const liability = ethers.zeroPadValue("0x03", 32);
    const counterparty = ethers.zeroPadValue("0x04", 32);
    await expect(positioned.emitPositioned(account, asset, 100n, liability, 25n, counterparty, 7))
      .to.emit(positioned, "Positioned")
      .withArgs(account, asset, 100n, liability, 25n, counterparty, 7);
  });
});

describe("Balance events", () => {
  const signatures = [
    "event Balance(bytes32 indexed account, bytes32 asset, uint balance, int change)",
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
    for (const change of [30n, -30n, 0n]) {
      it(`${name} indexes its owner and encodes change ${change}`, async () => {
        const emitter = await deploy("TestBalanceEvents");
        const asset = ethers.zeroPadValue("0x11", 32);
        const receipt = await (await emitter[method](owner, asset, 70n, change)).wait();
        const decoder = new ethers.Interface([signatures[index]!]);
        expect(receipt.logs).to.have.length(1);
        const log = receipt.logs[0];
        expect(log.topics).to.deep.equal([
          decoder.getEvent(name)!.topicHash,
          ethers.toBeHex(BigInt(owner), 32),
        ]);
        expect(ethers.dataLength(log.data)).to.equal(96);
        expect(Array.from(decoder.parseLog(log)!.args)).to.deep.equal([
          owner, asset, 70n, change,
        ]);
      });
    }
  }
});
