import { expect } from "chai";
import { ethers } from "ethers";
import { deploy } from "./helpers/setup.js";
import { blockKey, encodeBlock, encodeStringBlock, exactSpec, rangedSpec, Keys } from "./helpers/blocks.js";
import "./helpers/matchers.js";

const amountKey = blockKey("#amount");
const amount = exactSpec(amountKey, 32);
const encoded = (lane: bigint, body: string) => encodeBlock(blockKey("#lane"),
  ethers.concat([ethers.toBeHex(lane, 32), encodeStringBlock(body)]));

describe("Lane annotations", () => {
  it("hashes exact string bytes for lanes and exact/ranged schemas", async () => {
    const host = await deploy("TestLaneAnnotation");
    for (const name of ["addPool", "#amount", "", "Pool.λ"]) {
      const key = blockKey(name);
      const body = "#amount[2] as (a, b)";
      const lane = amount | BigInt(key);
      expect(await host.publishNamed.staticCall(body, name, amount))
        .eq(await host.publish.staticCall(body, BigInt(key), amount));
      await expect(host.publishNamed(body, name, amount)).to.emitMetadata(host)
        .withArgs(await host.host(), encoded(lane, body));
      const schemaBody = "local: uint value";
      const exact = exactSpec(key, 32), ranged = rangedSpec(key, 8, 0, 128);
      expect(await host.schemaExact.staticCall(schemaBody, name, 32)).eq(exact);
      expect(await host.schemaRange.staticCall(schemaBody, name, 8, 0, 128)).eq(ranged);
      for (const [send, spec] of [
        [() => host.schemaExact(schemaBody, name, 32), exact],
        [() => host.schemaRange(schemaBody, name, 8, 0, 128), ranged],
      ] as const) {
        await expect(send()).to.emitMetadata(host).withArgs(await host.host(),
          encodeBlock(blockKey("#schema"), ethers.concat([ethers.toBeHex(spec, 32), encodeStringBlock(schemaBody)])));
      }
    }
    await expect(host.publishNamed("#amount", "addPool", amount | 1n))
      .revertedWithCustomError(host, "InvalidSpec");
  });

  it("publishes host-scoped lane metadata and retains the complete lane in endpoint discovery", async () => {
    const host = await deploy("TestLaneAnnotation");
    const lane = amount | 1n;
    expect(await host.inputLane()).eq(lane);
    await expect(host.deploymentTransaction()).to.emitMetadata(host)
      .withArgs(await host.host(), encoded(lane, "#amount[2] as (first, second)"));
    await expect(host.deploymentTransaction()).to.emitEndpoint(host)
      .withArgs(await host.commandId(), 0n, lane, amount);
    expect(await host.descriptor()).eq(await host.describe(0n, amount, amount));
    expect(Array.from(await host.catalog())).deep.eq([
      rangedSpec(blockKey("#lane"), 40, 0, 128), "uint lane, #string as body",
    ]);
  });

  it("publishes replacements without parsing the DSL and keeps block schemas separate", async () => {
    const host = await deploy("TestLaneAnnotation");
    for (const body of ["#amount as (left, right)", "", "invalid syntax", "λ".repeat(200)]) {
      expect(await host.publish.staticCall(body, 1, amount)).eq(amount | 1n);
      await expect(host.publish(body, 1, amount)).to.emitMetadata(host)
        .withArgs(await host.host(), encoded(amount | 1n, body));
    }
    await expect(host.publishSchema("uint amount", amount)).to.emitMetadata(host)
      .withArgs(await host.host(), encodeBlock(blockKey("#schema"),
        ethers.concat([ethers.toBeHex(amount, 32), encodeStringBlock("uint amount")])));
  });

  it("ignores lane identifiers in all descriptor lanes but rejects reserved bits", async () => {
    const host = await deploy("TestLaneAnnotation");
    for (const [state, input, output] of [[0n, amount, amount], [amount, amount, exactSpec(Keys.Position, 160)]]) {
      expect(await host.describe(state ? state | 0xffffffffn : 0n, input | 7n, output | 9n))
        .eq(await host.describe(state, input, output));
    }
    for (const bit of [32n, 64n, 127n, 128n, 135n]) {
      for (const index of [0, 1, 2]) {
        const lanes = [amount, amount, amount];
        lanes[index] = amount | (1n << bit);
        await expect(host.describe(...lanes)).revertedWithCustomError(host, "InvalidSpec");
      }
    }
    for (const [key, spec] of [[0n, amount], [1n, 0n], [1n, amount | 2n], [1n, amount | (1n << 135n)]]) {
      await expect(host.publish("#amount[2] as (a, b)", key, spec)).revertedWithCustomError(host, "InvalidSpec");
    }
  });

  it("preserves allocation and decoding for exact, divisible-hint, and key-count fallback paths", async () => {
    const host = await deploy("TestLaneAnnotation");
    const input = ethers.concat([1n, 2n, 3n, 4n].map(n => encodeBlock(amountKey, ethers.toBeHex(n, 32))));
    for (const source of [amount, rangedSpec(amountKey, 32, 0, 32), rangedSpec(amountKey, 32, 0, 33)]) {
      const plain = await host.copy(input, source, amount);
      const named = await host.copy(input, source | 0xffffffffn, amount | 7n);
      expect(Array.from(named)).deep.eq(Array.from(plain));
      expect(named.capacity).eq(160n);
      expect(named.output).eq(input);
    }
  });
});
