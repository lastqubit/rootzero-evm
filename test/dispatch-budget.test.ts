import { expect } from "chai";
import { deploy, getProvider, getSigner, hostId } from "./helpers/setup.js";
import { concat, encodeDispatchBlock } from "./helpers/blocks.js";
import "./helpers/matchers.js";

describe("Dispatch budget credit", () => {
  for (const spending of [[3n], [2n, 3n], [8n]]) {
    it(`returns only the remainder after spending ${spending.join(" + ")} wei`, async () => {
      const host = await deploy("TestDispatchBudget");
      const provider = await getProvider();
      const recipient = await (await getSigner(2)).getAddress();
      const portal = await hostId(recipient);
      const budget = 8n;
      const spent = spending.reduce((total, value) => total + value, 0n);
      const input = concat(...spending.map(value => encodeDispatchBlock(portal, value, "0x")));

      expect(await host.portDispatchPayable.staticCall(input, { value: budget }))
        .to.deep.equal(["0x", budget - spent]);

      const tx = await host.portDispatchPayable(input, { value: budget });
      const receipt = await tx.wait();
      let remaining = budget;
      for (const value of spending) {
        remaining -= value;
        await expect(tx).to.emit(host, "DispatchSpent").withArgs(value, remaining);
      }
      const before = await provider.getBalance(recipient, receipt!.blockNumber - 1);
      const after = await provider.getBalance(recipient, receipt!.blockNumber);
      expect(after - before).to.equal(spent);
      expect(await provider.getBalance(await host.getAddress(), receipt!.blockNumber))
        .to.equal(budget - spent);
    });
  }

  it("rejects cumulative overspending and rolls back earlier dispatch transfers", async () => {
    const host = await deploy("TestDispatchBudget");
    const provider = await getProvider();
    const recipient = await (await getSigner(2)).getAddress();
    const portal = await hostId(recipient);
    const input = concat(
      encodeDispatchBlock(portal, 5n, "0x"),
      encodeDispatchBlock(portal, 4n, "0x"),
    );
    const before = BigInt(await provider.send("eth_getBalance", [recipient, "latest"]));
    await expect(host.portDispatchPayable(input, { value: 8n, gasLimit: 500_000n }))
      .to.be.revertedWithCustomError(host, "InsufficientValue");
    expect(BigInt(await provider.send("eth_getBalance", [recipient, "latest"]))).to.equal(before);
    expect(BigInt(await provider.send("eth_getBalance", [await host.getAddress(), "latest"]))).to.equal(0n);
  });
});
