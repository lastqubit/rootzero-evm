import { expect } from "chai";
import { ethers } from "ethers";
import { deploy, getSigner, getProvider, hostId } from "./helpers/setup.js";
import "./helpers/matchers.js";
import { encodeAccountBlock, encodeCallBlock, encodeContextBlock, encodeEntityBlock, encodeUserAccount } from "./helpers/blocks.js";

describe("Sweep, chain nodes and local guardians", () => {
  async function setup() {
    const commander = await getSigner(0);
    const other = await getSigner(1);
    const provider = await getProvider();
    const host: any = await deploy("TestHost", await hostId(await commander.getAddress()));
    const address = await host.getAddress();
    await commander.sendTransaction({ to: address, value: 1000n });
    const admin = await host.getAdminAccount();
    const { chainId } = await provider.getNetwork();
    return { commander, other, provider, host, address, admin, chainId };
  }

  describe("sweep", () => {
    it("sends a stated amount to the commander when the commander calls", async () => {
      const f = await setup();
      await f.host.connect(f.commander).sweep(400n);
      expect(await f.provider.getBalance(f.address)).to.equal(600n);
    });

    it("works through the host's own executePayable with no value", async () => {
      const f = await setup();
      const data = f.host.interface.encodeFunctionData("sweep", [400n]);
      const input = encodeCallBlock(await hostId(f.address), 0n, data);
      await f.host.connect(f.commander).executePayable(encodeContextBlock(f.admin, "0x", input));
      expect(await f.provider.getBalance(f.address)).to.equal(600n);
    });

    it("rejects anyone else", async () => {
      const f = await setup();
      await expect(f.host.connect(f.other).sweep(1n)).to.be.revertedWithCustomError(f.host, "AccessDenied");
      expect(await f.provider.getBalance(f.address)).to.equal(1000n);
    });

    it("reverts when the host doesn't hold the amount", async () => {
      const f = await setup();
      await expect(f.host.connect(f.commander).sweep(1001n)).to.be.revertedWithCustomError(f.host, "SendFailed");
    });
  });

  describe("chain nodes in the trusted set", () => {
    const authorize = async (f: Awaited<ReturnType<typeof setup>>, id: bigint) =>
      f.host.connect(f.commander).authorize(encodeContextBlock(f.admin, "0x", encodeEntityBlock(id)));

    it("accepts another chain's chain node", async () => {
      const f = await setup();
      const node = (0x03020100n << 224n) | ((f.chainId + 1n) << 192n);
      await authorize(f, node);
      expect(await f.host.isAuthorized(node)).to.equal(true);
    });

    it("still rejects another chain's other nodes, and anything shaped almost like a chain node", async () => {
      const f = await setup();
      const remote = (f.chainId + 1n) << 192n;
      for (const id of [
        (0x03020200n << 224n) | remote | 1n, // a host
        (0x03020300n << 224n) | remote | 1n, // a command
        (0x03020100n << 224n) | remote | 1n, // a chain node with a payload
        (0x03020101n << 224n) | remote, // a chain node with flags
      ]) {
        await expect(authorize(f, id)).to.be.revertedWithCustomError(f.host, "InvalidId");
      }
    });
  });

  describe("guardians", () => {
    const appoint = async (f: Awaited<ReturnType<typeof setup>>, account: string) =>
      f.host.connect(f.commander).appoint(encodeContextBlock(f.admin, "0x", encodeAccountBlock(account)));

    it("appoints this chain's user account, and rejects another chain's", async () => {
      const f = await setup();
      const address = await f.other.getAddress();
      await expect(appoint(f, encodeUserAccount(address, f.chainId + 1n))).to.be.revertedWithCustomError(f.host, "InvalidAccount");
      await appoint(f, encodeUserAccount(address, f.chainId));
      expect(await f.host.isGuardianAddress(address)).to.equal(true);
    });

    it("can dismiss another chain's account, which does nothing", async () => {
      const f = await setup();
      const account = encodeUserAccount(await f.other.getAddress(), f.chainId + 1n);
      await f.host.connect(f.commander).dismiss(encodeContextBlock(f.admin, "0x", encodeAccountBlock(account)));
    });
  });
});
