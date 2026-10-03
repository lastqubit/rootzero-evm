import { expect } from "chai";
import { ethers } from "ethers";
import { deploy } from "./helpers/setup.js";
import "./helpers/matchers.js";

const word = (n: bigint) => ethers.toBeHex(n, 32);
const asset = word(123n);
const block = (key: string, payload: string) => ethers.concat([
    ethers.id(`#${key}`).slice(0, 10), ethers.toBeHex(ethers.getBytes(payload).length, 4), payload,
]);
const balance = block("balance", ethers.concat([asset, word(7n)]));
const amount = block("assetAmount", ethers.concat([asset, word(3n)]));
const context = (state: string, input: string) => block("context", ethers.concat([
    word(1n), block("state", state), block("input", input),
]));

describe("Command runner validation", function () {
    it("preserves account, both metadata-free cursors, writer capacity, and full-width budget", async function () {
        const helper = await deploy("TestCommandContext");
        const key = BigInt(ethers.id("#balance").slice(0, 10));
        const max = (1n << 256n) - 1n;
        for (const flags of [0n, 1n, 2n, 3n]) {
            const descriptor = (key << 224n) | (72n << 192n) | (72n << 160n) | 1n | (flags << 1n);
            const [exec, offset] = await helper.inspect(context(balance, amount), descriptor, max);
            const state = offset + 48n;
            const end = state + 72n;
            const input = end + 8n;
            expect(exec.account).to.equal(word(1n));
            expect(exec.input).to.equal(input | ((input + 72n) << 32n));
            expect(exec.state).to.equal(state | (end << 32n));
            expect(exec.output).to.equal(72n << 32n);
            // 72 logical bytes rounded to 96, plus one retained scratch word.
            // The unwritten contents are deliberately unspecified.
            expect(ethers.dataLength(exec.buffer)).to.equal(128);
            expect(exec.budget).to.equal(max);
        }
    });

    it("runs empty, input-only, state-only, and paired batches without cursor flags", async function () {
        const runner = await deploy("CommandRunnerBenchmark");
        for (const mode of [0, 1, 2, 3]) for (const count of [0, 1, 3]) {
            const state = mode === 2 ? "0x" : ethers.concat(Array(count).fill(balance));
            const input = mode >= 2 ? ethers.concat(Array(count).fill(amount)) : "0x";
            const resultBlock = mode === 2 ? block("balance", ethers.concat([asset, word(3n)]))
                : mode === 3 ? block("balance", ethers.concat([asset, word(10n)])) : balance;
            const expected = mode === 0 ? "0x" : ethers.concat(Array(count).fill(resultBlock));
            expect(await runner.batch.staticCall(context(state, input), mode, { value: 23n })).deep.eq([expected, 23n]);
        }
    });

    it("rejects uint32 capacity overflow before allocation on fixed-size and scanned paths", async function () {
        const helper = await deploy("TestCommandContext");
        const key = BigInt(ethers.id("#balance").slice(0, 10));
        const max = 0xffffffffn;
        for (const blockSize of [0n, 72n]) {
            const descriptor = (key << 224n) | (blockSize << 192n) | (max << 160n) | 1n;
            // Opening is eager: a max-capacity output would require a 4 GiB
            // allocation, so test practical allocation and overflow separately.
            const practical = (descriptor & ~(max << 160n)) | (72n << 160n);
            const [exec] = await helper.inspect(context(balance, "0x"), practical, 0n);
            expect(exec.output).to.equal(72n << 32n);
            expect(ethers.dataLength(exec.buffer)).to.equal(128);
            await expect(helper.inspect(context(ethers.concat([balance, balance]), "0x"), descriptor, 0n))
                .to.be.revertedWithCustomError(helper, "ValueOverflow");
        }
    });

    it("retains malformed-context, source-consumption, and once-only behavior", async function () {
        const runner = await deploy("CommandRunnerBenchmark");
        const valid = context(balance, "0x");
        for (const data of ["0x", ethers.concat([valid, "0x00"]), valid.slice(0, -2),
            context("0x00", "0x"), context(balance, amount), context("0x", amount)]) {
            let reverted = false;
            try { await runner.batch.staticCall(data, 1); } catch (error: any) {
                expect(error.data).to.be.a("string");
                reverted = true;
            }
            expect(reverted).to.equal(true);
        }
        for (const offset of [0, 40, 120]) {
            const bytes = ethers.getBytes(valid);
            bytes[offset] ^= 0xff;
            await expect(runner.batch(bytes, 1)).to.be.revertedWithCustomError(runner, "InvalidBlock");
        }
        await expect(runner.batch(context(balance, "0x"), 3)).to.be.revertedWithCustomError(runner, "InvalidBlock");
        await expect(runner.batch(context(balance, ethers.concat([amount, amount])), 3)).to.be.revertedWithCustomError(runner, "InvalidBlock");
        expect(await runner.single.staticCall(valid, { value: 23n })).to.deep.equal([balance, 23n]);
        await expect(runner.single(context("0x", "0x"))).to.be.revertedWithCustomError(runner, "InvalidBlock");
        await expect(runner.single(context(ethers.concat([balance, balance]), "0x"))).to.be.revertedWithCustomError(runner, "UnconsumedData");
    });
});
