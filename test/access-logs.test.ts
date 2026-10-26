import { expect } from "chai";
import { ethers } from "ethers";
import { commandId, deploy, getSigner, hostId } from "./helpers/setup.js";
import { concat, encodeAccountBlock, encodeContextBlock, encodeEntityBlock, encodeUserAccount } from "./helpers/blocks.js";
import { Category, eventRecord, word } from "./helpers/event-records.js";
import "./helpers/matchers.js";

describe("Node Access events", () => {
  it("records only Access transitions, including guardian revocation", async () => {
    const host = await deploy("TestHost", await hostId(await (await getSigner(0)).getAddress()));
    const account = await host.getAdminAccount();
    const node = await hostId(await (await getSigner(4)).getAddress());
    const input = encodeEntityBlock(node);
    const context = (data: string) => encodeContextBlock(account, "0x", data);
    const records = async (tx: Promise<any>) => (await (await tx).wait()).logs;
    const expectTransition = (logs: any[], enabled: boolean) => {
      expect(logs).length(1);
      expect(logs[0].topics).deep.eq([]);
      expect(logs[0].data).eq(eventRecord(Category.Trust, word(node), enabled ? "0x01" : "0x00"));
    };
    expectTransition(await records(host.authorize(context(concat(input, input)))), true);
    expect(await host.isAuthorized(node)).eq(true);
    expect(await records(host.authorize(context(input)))).length(0);
    expectTransition(await records(host.unauthorize(context(concat(input, input)))), false);
    expect(await host.isAuthorized(node)).eq(false);
    expect(await records(host.unauthorize(context(input)))).length(0);

    const guardian = await getSigner(1);
    const guardianInput = encodeAccountBlock(encodeUserAccount(await guardian.getAddress()));
    // Guardian changes are not Access records, and endpoints emit no execution records.
    expect(await records(host.appoint(context(guardianInput)))).length(0);
    await host.authorize(context(input));
    expectTransition(await records((host.connect(guardian) as any).revoke(input)), false);
    expect(await host.isAuthorized(node)).eq(false);
    expect(await records(host.dismiss(context(guardianInput)))).length(0);
  });

  it("rolls back a grant when a later node in the batch is invalid", async () => {
    const host = await deploy("TestHost", await hostId(await (await getSigner(0)).getAddress()));
    const node = await hostId(await (await getSigner(4)).getAddress());
    await expect(host.authorize(encodeContextBlock(await host.getAdminAccount(), "0x",
      concat(encodeEntityBlock(node), encodeEntityBlock(0n)))))
      .revertedWithCustomError(host, "InvalidId");
    expect(await host.isAuthorized(node)).eq(false);
  });
  it("keeps access grants distinct when only logging hint bits differ", async () => {
    const host = await deploy("TestHost", await hostId(await (await getSigner(0)).getAddress()));
    const logged = await commandId("withdraw(bytes)", host);
    expect((logged >> 224n) & 255n).eq(8n);
    const silent = logged & ~(56n << 224n);
    const account = await host.getAdminAccount();
    const context = (node: bigint) => encodeContextBlock(account, "0x", encodeEntityBlock(node));
    await host.authorize(context(logged));
    expect(await host.isAuthorized(logged)).eq(true);
    expect(await host.isAuthorized(silent)).eq(false);
    await host.unauthorize(context(silent));
    expect(await host.isAuthorized(logged)).eq(true);
    await host.unauthorize(context(logged));
    expect(await host.isAuthorized(logged)).eq(false);
  });

});
