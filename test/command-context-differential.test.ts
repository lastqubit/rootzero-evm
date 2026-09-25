import { expect } from "chai";
import { writeFileSync } from "node:fs";
import { ethers } from "ethers";
import { deploy } from "./helpers/setup.js";

describe("Command context differential corpus", function () {
    it("records exact output or revert bytes for valid and malformed contexts", async function () {
        const runner = await deploy("CommandRunnerBenchmark");
        const block = (key: string, data: string) => ethers.concat([
            ethers.id(`#${key}`).slice(0, 10), ethers.toBeHex(ethers.getBytes(data).length, 4), data,
        ]);
        const balance = block("balance", ethers.concat([ethers.toBeHex(123, 32), ethers.toBeHex(7, 32)]));
        const amount = block("amount", ethers.concat([ethers.toBeHex(123, 32), ethers.toBeHex(3, 32)]));
        const outcomes: string[] = [];
        const abi = ethers.AbiCoder.defaultAbiCoder();
        for (const mode of [0, 1, 2, 3, 4]) {
            const state = ethers.concat(Array(mode === 2 ? 0 : 2).fill(balance));
            const input = ethers.concat(Array(mode === 2 || mode === 3 ? 2 : 0).fill(amount));
            const valid = ethers.getBytes(block("context", ethers.concat([
                ethers.toBeHex(1, 32), block("bytes", state), block("bytes", input),
            ])));
            const vectors: Uint8Array[] = [valid, new Uint8Array([...valid, ...valid]), new Uint8Array([...valid, 0])];
            for (let length = 0; length < valid.length; length += 7) vectors.push(valid.slice(0, length));
            for (const header of [0, 40, 48 + ethers.getBytes(state).length]) {
                const badKey = valid.slice();
                badKey[header] ^= 255;
                vectors.push(badKey);
                for (const size of [0, 1, 7, 8, 32, 64, 72, 144, 0xffffffff]) {
                    const changed = valid.slice();
                    changed.set(ethers.getBytes(ethers.toBeHex(size, 4)), header + 4);
                    vectors.push(changed);
                }
            }
            for (const data of vectors) {
                try {
                    const out = mode === 4 ? await runner.single.staticCall(data, { value: 19n })
                        : await runner.batch.staticCall(data, mode, { value: 19n });
                    outcomes.push(abi.encode(["bool", "bytes", "uint256"], [true, out[0], out[1]]));
                } catch (error: any) {
                    expect(error.data, "Expected EVM revert data, not a provider/setup error").to.be.a("string");
                    outcomes.push(abi.encode(["bool", "bytes", "uint256"], [false, error.data, 0]));
                }
            }
        }
        const result = { cases: outcomes.length, digest: ethers.keccak256(ethers.concat(outcomes)) };
        // Recorded before changing either runner helper, with Solidity 0.8.33,
        // viaIR and optimizer 200. Includes exact output, credit and revert bytes.
        expect(result).to.deep.equal({
            cases: 331,
            digest: "0x07a54e4b915a07b3a309a9399c2b20f81f1ae3d21a69c64dbf1a3253ee73b7c3",
        });
        writeFileSync("cache/command-context-corpus.json", JSON.stringify(result, null, 2) + "\n");
        console.log(result);
    });
});
