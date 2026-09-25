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
const amount = block("amount", ethers.concat([asset, word(3n)]));
const context = (state: string, input: string) => block("context", ethers.concat([
    word(1n), block("bytes", state), block("bytes", input),
]));

describe("Command runner validation", function () {
    it("preserves account, both cursor lanes, declared flags, writer capacity, and full-width budget", async function () {
        const helper = await deploy("TestCommandContext");
        const key = BigInt(ethers.id("#balance").slice(0, 10));
        const max = (1n << 256n) - 1n;
        for (const flags of [0n, 1n, 2n, 3n]) {
            const descriptor = (key << 160n) | (key << 128n) | (72n << 96n)
                | (72n << 64n) | (64n << 56n) | (flags << 48n);
            const [exec, offset] = await helper.inspect(context(balance, amount), descriptor, max);
            const state = offset + 48n;
            const end = state + 72n;
            const input = end + 8n;
            expect(exec.account).to.equal(word(1n));
            expect(exec.decoders).to.equal(input | ((input + 72n) << 32n)
                | (state << 64n) | (end << 96n) | (flags << 128n));
            expect(exec.writer).to.equal(72n << 32n);
            expect(exec.output).to.equal("0x");
            expect(exec.budget).to.equal(max);
        }
    });

    it("retains the uint32 capacity limit on fixed-size and scanned counting paths", async function () {
        const helper = await deploy("TestCommandContext");
        const key = BigInt(ethers.id("#balance").slice(0, 10));
        const max = 0xffffffffn;
        for (const blockSize of [0n, 72n]) {
            const descriptor = (key << 160n) | (key << 128n) | (blockSize << 96n)
                | (max << 64n) | (64n << 56n) | (1n << 48n);
            const [exec] = await helper.inspect(context(balance, "0x"), descriptor, 0n);
            expect(exec.writer).to.equal(max << 32n);
            expect(exec.output).to.equal("0x"); // A hint does not allocate memory.
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
        await expect(runner.batch(context(balance, "0x"), 3)).to.be.revertedWithCustomError(runner, "OutOfBounds");
        await expect(runner.batch(context(balance, ethers.concat([amount, amount])), 3)).to.be.revertedWithCustomError(runner, "OutOfBounds");
        expect(await runner.single.staticCall(valid, { value: 23n })).to.deep.equal([balance, 23n]);
        await expect(runner.single(context("0x", "0x"))).to.be.revertedWithCustomError(runner, "OutOfBounds");
        await expect(runner.single(context(ethers.concat([balance, balance]), "0x"))).to.be.revertedWithCustomError(runner, "UnconsumedData");
    });
});
