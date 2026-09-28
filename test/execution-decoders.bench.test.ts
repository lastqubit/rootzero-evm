import { expect } from "chai";
import { ethers } from "ethers";
import { writeFileSync } from "node:fs";
import { deploy } from "./helpers/setup.js";
import { encodeBlock } from "./helpers/blocks.js";
import { decoderLayouts } from "./helpers/decoder-layouts.js";

describe("Execution fixed cursor decoder gas", () => {
  it("compares complete decoding and cursor advancement against the old Blocks adapter", async () => {
    const helper = await deploy("TestExecutionDecoders");
    const rows: { block: string; before: number; after: number; saved: number }[] = [];
    for (const [kind, layout] of decoderLayouts.entries()) {
      const key = ethers.id("#" + layout.name[0].toLowerCase() + layout.name.slice(1)).slice(0, 10);
      const source = encodeBlock(key, "0x" + "ab".repeat(layout.words * 32));
      const before = await helper.inspect(kind, source, ethers.dataLength(source), true);
      const after = await helper.inspect(kind, source, ethers.dataLength(source), false);
      expect(after.data).eq(before.data);
      expect(after.input).eq(before.input);
      expect(after.state).eq(before.state);
      rows.push({ block: layout.name, before: Number(before.usedGas), after: Number(after.usedGas), saved: Number(before.usedGas - after.usedGas) });
    }
    console.table(rows);
    writeFileSync(".npm-cache/execution-decoders-gas.json", JSON.stringify(rows, null, 2) + "\n");
  });
});
