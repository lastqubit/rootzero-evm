import { expect } from "chai";
import { ethers } from "ethers";
import { deploy, commandId } from "./helpers/setup.js";
import { encodeBlock, encodeStringBlock, endpointDescriptor, exactSpec, Keys } from "./helpers/blocks.js";
import "./helpers/matchers.js";

const groupsKey = ethers.id("#groups").slice(0, 10);
const encoded = (description: string) => encodeBlock(groupsKey, encodeStringBlock(description));

describe("Groups annotation", () => {
  it("publishes grouped lanes on the command without descriptor group bits", async () => {
    const description = "#state as (debit, credit), #output as (receipt, change)";
    const host = await deploy("TestGroupsAnnotation", description);
    const id = await commandId("grouped(bytes)", host);
    const descriptor = endpointDescriptor({ state: Keys.Balance, stateHint: 64, output: exactSpec(Keys.Position, 160) });
    expect(await host.commandId()).to.equal(id);
    expect(await host.descriptor()).to.equal(descriptor);
    await expect(host.deploymentTransaction()).to.emit(host, "Endpoint").withArgs(await host.host(), id, descriptor);
    await expect(host.deploymentTransaction()).to.emit(host, "Annotation").withArgs(id, encoded(description));
    const [spec, body] = await host.catalog();
    expect(ethers.toBeHex(spec >> 224n, 4)).to.equal(groupsKey);
    expect((spec >> 192n) & 0xffffffffn).to.equal(8n);
    expect(body).to.equal("#string as description");
  });

  it("emits replacements and an empty description to clear hints", async () => {
    const host = await deploy("TestGroupsAnnotation", "#state as (debit, credit)");
    for (const description of ["#output as (receipt, change)", ""]) {
      await expect(host.publish(description)).to.emit(host, "Annotation")
        .withArgs(await host.commandId(), encoded(description));
    }
  });

  it("preserves annotation strings without on-chain DSL validation", async () => {
    const host = await deploy("TestGroupsAnnotation", "");
    for (const description of ["#input as (left, right)", "invalid syntax", "?".repeat(200)]) {
      await expect(host.publish(description)).to.emit(host, "Annotation")
        .withArgs(await host.commandId(), encoded(description));
    }
  });
});
