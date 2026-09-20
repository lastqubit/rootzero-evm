import { expect } from "chai";
import { ethers } from "ethers";
import { deploy, commandId } from "./helpers/setup.js";
import { encodeBlock, exactSpec, pad32 } from "./helpers/blocks.js";
import "./helpers/matchers.js";

const key = ethers.id("#executionCost").slice(0, 10);
const encoded = (base: bigint, batch: bigint) =>
  encodeBlock(key, ethers.concat([pad32(base), pad32(batch)]));

describe("ExecutionCost annotation", () => {
  it("publishes a command estimate with the standard fixed-width schema", async () => {
    const host = await deploy("TestExecutionCostAnnotation", 10_000n, 5_000n);
    const id = await commandId("costed(bytes)", host);
    expect(await host.commandId()).to.equal(id);
    await expect(host.deploymentTransaction()).to.emit(host, "Annotation")
      .withArgs(id, encoded(10_000n, 5_000n));
    const [spec, body] = await host.catalog();
    expect(spec).to.equal(exactSpec(key, 64));
    expect(body).to.equal("uint base, uint batch");
  });

  it("encodes and publishes replacements across the full uint range", async () => {
    const host = await deploy("TestExecutionCostAnnotation", 1n, 2n);
    for (const [base, batch] of [
      [123n, 456n], [0n, 789n], [789n, 0n], [0n, 0n],
      [ethers.MaxUint256, ethers.MaxUint256],
    ]) {
      const data = encoded(base, batch);
      expect(await host.encode(base, batch)).to.equal(data);
      expect(ethers.dataLength(data)).to.equal(72);
      await expect(host.publish(base, batch)).to.emit(host, "Annotation")
        .withArgs(await host.commandId(), data);
    }
  });
});
