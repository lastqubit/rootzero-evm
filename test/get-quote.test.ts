import { expect } from "chai";
import { ethers } from "ethers";
import { deploy, queryId } from "./helpers/setup.js";
import { blockKey, encodeBlock, encodeQuoteBlock, exactSpec } from "./helpers/blocks.js";
import "./helpers/matchers.js";

const key = blockKey("#quoteRequest");
const spec = exactSpec(key, 96);
const request = (asset: string, amount: bigint, liability: string) =>
  encodeBlock(key, ethers.concat([asset, ethers.toBeHex(amount, 32), liability]));
const asset = ethers.toBeHex(1, 32), liability = ethers.toBeHex(2, 32);

async function expectRevert(call: Promise<unknown>) {
  await call.then(() => expect.fail("Expected an EVM revert"), (error: any) => {
    expect(error.data).to.be.a("string");
  });
}

describe("GetQuote and scalar QuoteRequest codec", () => {
  let host: Awaited<ReturnType<typeof deploy>>;
  before(async () => { host = await deploy("TestGetQuote"); });
  beforeEach(async () => {
    await host.configure(asset, liability, 7n);
    await host.configure(liability, asset, 11n);
  });

  it("publishes the request catalog and query input/output specs", async () => {
    expect(Array.from(await host.catalog())).deep.eq([
      spec, 104n, spec >> 192n, "bytes32 asset, uint amount, bytes32 liability",
    ]);
    await expect(host.deploymentTransaction()).to.emitEndpoint(host).withArgs(
      await queryId("getQuote(bytes)", host), 0n, spec, exactSpec(blockKey("#quote"), 128), "getQuote",
    );
  });

  it("round-trips scalar requests, retaining full-width values and exact cursor advancement", async () => {
    const wide = ethers.toBeHex(ethers.MaxUint256, 32);
    const values: [string, bigint, string][] = [[ethers.ZeroHash, 0n, ethers.ZeroHash], [asset, 123n, liability], [wide, ethers.MaxUint256, wide]];
    for (const [a, amount, b] of values) {
      const encoded = request(a, amount, b);
      expect(await host.create(a, amount, b)).eq(encoded);
      expect(await host.write(a, amount, b)).eq(encoded);
      expect(Array.from(await host.decode(ethers.concat([encoded, encoded])))).deep.eq([a, amount, b, 104n]);
    }
    const batch = ethers.concat(values.map(([a, amount, b]) => request(a, amount, b)));
    expect(await host.echo(batch)).eq(batch);
    expect(await host.echo("0x")).eq("0x");
  });

  it("returns complete quotes in request order using host pricing policy", async () => {
    const input = ethers.concat([request(asset, 100n, liability), request(liability, 20n, asset), request(asset, 0n, liability)]);
    expect(await host.getQuote(input)).eq(ethers.concat([
      encodeQuoteBlock(asset, 100n, liability, 107n),
      encodeQuoteBlock(liability, 20n, asset, 31n),
      encodeQuoteBlock(asset, 0n, liability, 7n),
    ]));
    expect(await host.getQuote("0x")).eq("0x");
    await host.configure(asset, liability, 0n);
    expect(await host.getQuote(request(asset, ethers.MaxUint256, liability)))
      .eq(encodeQuoteBlock(asset, ethers.MaxUint256, liability, ethers.MaxUint256));
  });

  it("rejects malformed requests and incomplete trailing requests", async () => {
    const valid = request(asset, 5n, liability);
    const payload = ethers.dataSlice(valid, 8);
    const malformed = [
      ...[1, 7, 8, 39, 71, 103].map(n => ethers.dataSlice(valid, 0, n)),
      encodeBlock(blockKey("#accountAmount"), payload),
      encodeBlock(key, ethers.dataSlice(payload, 0, 95)),
      encodeBlock(key, ethers.concat([payload, "0x00"])),
      ethers.concat([key, "0xffffffff", payload]),
    ];
    for (const bad of malformed) {
      await expectRevert(host.decode(bad));
      await expectRevert(host.getQuote(bad));
      await expectRevert(host.getQuote(ethers.concat([valid, bad])));
    }
  });

  it("propagates hook failures, including after an earlier valid request", async () => {
    const bad = request(asset, 1n, ethers.ZeroHash);
    await expect(host.getQuote(bad)).revertedWithCustomError(host, "UnsupportedPair");
    await expect(host.getQuote(ethers.concat([request(asset, 5n, liability), bad])))
      .revertedWithCustomError(host, "UnsupportedPair");
  });
});
