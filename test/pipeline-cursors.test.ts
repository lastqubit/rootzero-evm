import { expect } from "chai";
import { ethers } from "ethers";
import { deploy } from "./helpers/setup.js";
import { concat, encodeRelayBlock, encodeStepBlock } from "./helpers/blocks.js";

describe("Independent Pipeline input and stream cursors", () => {
  it("forwards exact handoff input and continuation, including an empty continuation", async () => {
    for (const name of ["TestPackedPipelineOptimization", "TestPipelineOptimization"]) {
      const host = await deploy(name);
      const handoff = (await host.externalId()) | (128n << 224n);
      await (await host.allow(handoff)).wait();
      let calls = 0n;
      for (const input of ["0x", "0x123456", "0x" + "ab".repeat(65)]) {
        for (const count of [0, 1, 4]) {
          const tail = concat(...Array(count).fill(encodeStepBlock(await host.localId(), 0n, "0x")));
          const steps = concat(encodeStepBlock(handoff, 0n, input), tail);
          await (await host.measure(steps, 0n, "0x")).wait();
          expect(await host.lastInput()).eq(ethers.keccak256(encodeRelayBlock(input, tail)));
          expect(await host.calls()).eq(++calls);
        }
      }
    }
  });
});
