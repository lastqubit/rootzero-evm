import { expect } from "chai";
import { ethers } from "ethers";
import { deploy, getSigner, hostId, commandId } from "./helpers/setup.js";
import { concat, encodeContextBlock, encodeOutputBlock, encodePositionBlock, encodeSwapBlock, encodeUserAccount, pad32 } from "./helpers/blocks.js";

describe("Swap output log gas", () => {
  it("measures empty, single and batched full-width output logs", async () => {
    const caller = await (await getSigner()).getAddress();
    const host = await deploy("TestSwapCommands", await hostId(caller));
    const account = encodeUserAccount(caller);
    const asset = pad32(1n), liability = pad32(2n), counterparty = pad32(3n);
    const rows: { method: string; quantities: string; count: number; logBytes: number; gas: number }[] = [];
    for (const method of ["swapExactIn", "swapExactOut"]) {
      const prefix = pad32(await commandId(method + "(bytes)", host));
      for (const amount of [10n ** 18n, ethers.MaxUint256]) {
        await (await host.configure([asset, amount, liability, amount, counterparty], false)).wait();
        // Normalize the hook counter to a nonzero-to-nonzero storage transition.
        await (await host[method](encodeContextBlock(account, "0x", encodeSwapBlock(asset, amount, liability)))).wait();
        for (const count of [0, 1, 4, 16]) {
          const input = concat(...Array(count).fill(encodeSwapBlock(asset, amount, liability)));
          const output = concat(...Array(count).fill(encodePositionBlock(asset, amount, liability, amount, counterparty)));
          const context = encodeContextBlock(account, "0x", input);
          expect(Array.from(await host[method].staticCall(context))).deep.eq([output, 0n]);
          const receipt = await (await host[method](context)).wait();
          const logs = receipt.logs.filter((log: any) => log.topics.length === 0);
          expect(logs.map((log: any) => log.data)).deep.eq([concat(prefix, encodeOutputBlock(output))]);
          rows.push({ method, quantities: amount === ethers.MaxUint256 ? "max" : "typical", count,
            logBytes: ethers.dataLength(logs[0].data), gas: Number(receipt.gasUsed) });
        }
      }
    }
    console.table(rows);
  });
});
