import { expect } from "chai";
import { ethers } from "ethers";
import { deploy } from "./helpers/setup.js";
import "./helpers/matchers.js";

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
