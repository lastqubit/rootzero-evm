import { expect } from "chai";
import { ethers } from "ethers";
import { deploy, getSigner } from "./helpers/setup.js";

const CURVE_ORDER = BigInt("0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364141");

describe("ECDSA", () => {
  let ecdsa: Awaited<ReturnType<typeof deploy>>;

  before(async () => {
    ecdsa = await deploy("TestECDSA");
  });

  it("matches ethers hashMessage for bytes32 payloads", async () => {
    const hash = ethers.id("test payload");
    const digest = await ecdsa.testToEthSignedMessageHash(hash);
    expect(digest).to.equal(ethers.hashMessage(ethers.getBytes(hash)));
  });

  it("recovers the signer from a valid 65-byte signature", async () => {
    const signer = await getSigner(0);
    const hash = ethers.id("recover");
    const signature = await signer.signMessage(ethers.getBytes(hash));
    const digest = ethers.hashMessage(ethers.getBytes(hash));
    expect(await ecdsa.testTryRecoverCalldata(digest, signature))
      .to.equal(await signer.getAddress());
  });

  it("returns zero for signatures with invalid length", async () => {
    const hash = ethers.id("wrong length");
    const digest = ethers.hashMessage(ethers.getBytes(hash));
    expect(await ecdsa.testTryRecoverCalldata(digest, ethers.hexlify(new Uint8Array(64))))
      .to.equal(ethers.ZeroAddress);
    expect(await ecdsa.testTryRecoverCalldata(digest, ethers.hexlify(new Uint8Array(66))))
      .to.equal(ethers.ZeroAddress);
  });

  it("accepts y-parity signatures with v encoded as 0 or 1", async () => {
    const signer = await getSigner(0);
    const hash = ethers.id("y parity");
    const parsed = ethers.Signature.from(await signer.signMessage(ethers.getBytes(hash)));
    const paritySignature = ethers.concat([parsed.r, parsed.s, ethers.toBeHex(parsed.yParity, 1)]);
    const digest = ethers.hashMessage(ethers.getBytes(hash));
    expect(await ecdsa.testTryRecoverCalldata(digest, paritySignature))
      .to.equal(await signer.getAddress());
  });

  it("returns zero for signatures with invalid v", async () => {
    const signer = await getSigner(0);
    const hash = ethers.id("invalid v");
    const parsed = ethers.Signature.from(await signer.signMessage(ethers.getBytes(hash)));
    const invalidVSignature = ethers.concat([parsed.r, parsed.s, "0x02"]);
    const digest = ethers.hashMessage(ethers.getBytes(hash));
    expect(await ecdsa.testTryRecoverCalldata(digest, invalidVSignature))
      .to.equal(ethers.ZeroAddress);
  });

  it("returns zero for high-s signatures", async () => {
    const signer = await getSigner(0);
    const hash = ethers.id("high s");
    const parsed = ethers.Signature.from(await signer.signMessage(ethers.getBytes(hash)));
    const highS = ethers.toBeHex(CURVE_ORDER - BigInt(parsed.s), 32);
    const flippedV = parsed.v === 27 ? 28 : 27;
    const malleableSignature = ethers.concat([parsed.r, highS, ethers.toBeHex(flippedV, 1)]);
    const digest = ethers.hashMessage(ethers.getBytes(hash));
    expect(await ecdsa.testTryRecoverCalldata(digest, malleableSignature))
      .to.equal(ethers.ZeroAddress);
  });

  it("matches ethers for EIP-712 digests", async () => {
    const domain = { name: "rootzero", version: "1", chainId: 1, verifyingContract: ethers.ZeroAddress };
    const types = { Mail: [{ name: "contents", type: "string" }] };
    const value = { contents: "hello" };
    const digest = await ecdsa.testToTypedDataHash(
      ethers.TypedDataEncoder.hashDomain(domain),
      ethers.TypedDataEncoder.from(types).hash(value),
    );
    expect(digest).to.equal(ethers.TypedDataEncoder.hash(domain, types, value));
  });

  it("recovers the signer from compact signatures of both y parities", async () => {
    const signer = await getSigner(0);
    const seen = new Set<number>();
    for (let i = 0; seen.size < 2; i++) {
      const hash = ethers.id(`compact ${i}`);
      const parsed = ethers.Signature.from(await signer.signMessage(ethers.getBytes(hash)));
      seen.add(parsed.yParity);
      const digest = ethers.hashMessage(ethers.getBytes(hash));
      expect(await ecdsa.testTryRecoverCompact(digest, parsed.r, parsed.yParityAndS))
        .to.equal(await signer.getAddress());
    }
  });

  it("returns zero for compact signatures with high s under either y parity", async () => {
    const signer = await getSigner(0);
    const hash = ethers.id("compact high s");
    const parsed = ethers.Signature.from(await signer.signMessage(ethers.getBytes(hash)));
    const digest = ethers.hashMessage(ethers.getBytes(hash));
    const highS = CURVE_ORDER / 2n + 1n;
    for (const parity of [0n, 1n << 255n]) {
      expect(await ecdsa.testTryRecoverCompact(digest, parsed.r, ethers.toBeHex(parity | highS, 32)))
        .to.equal(ethers.ZeroAddress);
    }
  });

  it("returns zero for compact signatures that can't be recovered", async () => {
    const digest = ethers.id("compact zero r");
    expect(await ecdsa.testTryRecoverCompact(digest, ethers.ZeroHash, ethers.toBeHex(1, 32)))
      .to.equal(ethers.ZeroAddress);
  });
});


