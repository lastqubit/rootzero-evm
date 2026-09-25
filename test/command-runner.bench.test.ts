import { expect } from "chai";
import { writeFileSync } from "node:fs";
import { ethers } from "ethers";
import { deploy } from "./helpers/setup.js";

const word = (n: bigint) => ethers.toBeHex(n, 32);
const asset = word(123n);
const block = (key: string, payload: string) => ethers.concat([
    ethers.id(`#${key}`).slice(0, 10), ethers.toBeHex(ethers.getBytes(payload).length, 4), payload,
]);
const balance = block("balance", ethers.concat([asset, word(7n)]));
const amount = block("amount", ethers.concat([asset, word(3n)]));
const context = (state: string, input: string) => block("context", ethers.concat([
    word(1n), block("bytes", state), block("bytes", input),
]));

describe("Command runner gas", function () {
    it("measures empty, state-only, input-only, and paired batches with and without output", async function () {
        const runner = await deploy("CommandRunnerBenchmark");
        const rows: { mode: number; count: number; gas: number }[] = [];
        for (const mode of [0, 1, 2, 3]) {
            for (const count of [0, 1, 4, 16, 64]) {
                const state = ethers.concat(Array(mode === 2 ? 0 : count).fill(balance));
                const input = ethers.concat(Array(mode >= 2 ? count : 0).fill(amount));
                const data = context(state, input);
                const expected = mode === 0 ? "0x" : ethers.concat(Array(count).fill(block("balance",
                    ethers.concat([asset, word(mode === 3 ? 10n : mode === 2 ? 3n : 7n)]))));
                expect(await runner.batch.staticCall(data, mode, { value: 17n })).to.deep.equal([expected, 17n]);
                const receipt = await (await runner.batch(data, mode)).wait();
                rows.push({ mode, count, gas: Number(receipt!.gasUsed) });
            }
        }
        console.table(rows);
        writeFileSync("cache/command-runner-gas.json", JSON.stringify({ rows }, null, 2) + "\n");
    });

});
