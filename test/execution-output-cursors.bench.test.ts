import { expect } from "chai";
import { ethers } from "ethers";
import { writeFileSync } from "node:fs";
import { deploy } from "./helpers/setup.js";
import { encodeBlock, Keys } from "./helpers/blocks.js";

describe("Execution whole-block versus payload output cursors", () => {
  it("compares repeated writes with ready source cursors and sufficient initial capacity", async () => {
    const helper = await deploy("TestExecutionOutputCursors");
    const names = ["Block", "List", "Bytes", "String", "Step", "Call", "Dispatch", "Relay", "Context", "Recover", "Label", "Schema"];
    const overhead = [8, 8, 8, 8, 80, 80, 80, 24, 56, 112, 48, 48];
    const rows: { name: string; size: number; count: number; wrap: number; whole: number; saved: number }[] = [];
    for (const [kind, name] of names.entries()) for (const size of [0, 33, 256]) for (const count of [1, 4]) {
      const a = "0x" + "ab".repeat(size), b = "0x" + "cd".repeat(size % 35);
      const key = kind === 1 ? Keys.List : kind === 3 || kind >= 10 ? Keys.String : Keys.Bytes;
      const frame = (data: string) => ethers.concat(["0xfe", data, "0xef"]);
      const capacity = 40 + count * (overhead[kind] + size + (kind === 7 || kind === 8 ? size % 35 : 0));
      const wrap = await helper.encode(kind, frame(a), frame(b), count, capacity, false);
      const whole = await helper.encode(kind, frame(encodeBlock(key, a)), frame(encodeBlock(Keys.Bytes, b)), count, capacity, true);
      expect(whole.output).eq(wrap.output);
      expect(ethers.dataLength(whole.output)).eq(capacity);
      rows.push({ name, size, count, wrap: Number(wrap.usedGas), whole: Number(whole.usedGas), saved: Number(wrap.usedGas - whole.usedGas) });
    }
    console.table(rows.filter(row => row.size === 33 && row.count === 1));
    writeFileSync(".npm-cache/execution-output-cursors-gas.json", JSON.stringify(rows, null, 2) + "\n");
  });
});
