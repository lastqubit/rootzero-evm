import { expect } from "chai";
import { ethers } from "ethers";
import { deploy, queryId } from "./helpers/setup.js";
import "./helpers/matchers.js";
import {
  concat,
  encodeBlock,
  endpointDescriptor,
  encodeLabelBlock,
  encodeSchemaBlock,
  exactSpec,
  localKey,
  pad32,
} from "./helpers/blocks.js";

const Value = localKey(1);
const KeyedValue = localKey(2);
const ValueSpec = exactSpec(Value, 32);
const KeyedValueSpec = exactSpec(KeyedValue, 32);
const RelayInput = localKey(3);
const RelayInputSpec = exactSpec(RelayInput, 64);

describe("Queries", () => {
  let query: Awaited<ReturnType<typeof deploy>>;
  let keyedQuery: Awaited<ReturnType<typeof deploy>>;

  before(async () => {
    query = await deploy("TestQuery");
    keyedQuery = await deploy("TestKeyedLocalQuery");
  });

  async function qry(method: string) {
    return queryId(query.interface.getFunction(method)!.selector, query);
  }

  it("emits Endpoint discovery events with query id as the second argument", async () => {
    const tx = query.deploymentTransaction();
    expect(tx).to.not.equal(null);

    await expect(tx!)
      .to.emit(query, "Endpoint")
      .withArgs(
        await query.host(),
        await qry("incrementQuery"),
        endpointDescriptor({ input: Value, inputHint: 32, output: ValueSpec }),
      );
    await expect(tx!)
      .to.emit(query, "Annotation")
      .withArgs(await query.host(), encodeSchemaBlock(ValueSpec, "uint value"));
    await expect(tx!)
      .to.emit(query, "Annotation")
      .withArgs(await qry("incrementQuery"), encodeLabelBlock(ethers.ZeroHash, "incrementQuery"));
  });

  describe("incrementQuery", () => {
    it("accepts custom value blocks and returns custom value blocks", async () => {
      const input = encodeBlock(Value, pad32(7n));

      const result: string = await query.incrementQuery.staticCall(input);

      expect(result).to.equal(encodeBlock(Value, pad32(8n)));
    });

    it("maps multiple custom query blocks into matching response blocks", async () => {
      const input = concat(
        encodeBlock(Value, pad32(11n)),
        encodeBlock(Value, pad32(22n)),
      );

      const result: string = await query.incrementQuery.staticCall(input);

      expect(result).to.equal(concat(
        encodeBlock(Value, pad32(12n)),
        encodeBlock(Value, pad32(23n)),
      ));
    });
  });

  describe("keyedLocalQuery", () => {
    async function keyedQry(method: string) {
      return queryId(keyedQuery.interface.getFunction(method)!.selector, keyedQuery);
    }

    it("emits a schema annotation for a keyed local schema", async () => {
      const tx = keyedQuery.deploymentTransaction();
      expect(tx).to.not.equal(null);

      await expect(tx!)
        .to.emit(keyedQuery, "Endpoint")
        .withArgs(
          await keyedQuery.host(),
          await keyedQry("keyedLocalQuery"),
          endpointDescriptor({ input: KeyedValue, inputHint: 32, output: KeyedValueSpec }),
        );
      await expect(tx!)
        .to.emit(keyedQuery, "Annotation")
        .withArgs(await keyedQuery.host(), encodeSchemaBlock(KeyedValueSpec, "{ uint value }"));
    });

    it("accepts the keyed local value block", async () => {
      const input = encodeBlock(KeyedValue, pad32(7n));

      const result: string = await keyedQuery.keyedLocalQuery.staticCall(input);

      expect(result).to.equal(encodeBlock(KeyedValue, pad32(9n)));
    });
  });
});

describe("Qualified schemas", () => {
  it("publishes a relay.input block-stream binding with the existing helper", async () => {
    const schema = await deploy("TestQualifiedSchema");
    const tx = schema.deploymentTransaction();
    expect(tx).to.not.equal(null);

    await expect(tx!)
      .to.emit(schema, "Annotation")
      .withArgs(
        await schema.host(),
        encodeSchemaBlock(
          RelayInputSpec,
          "relay.input: uint portal, uint resources",
        ),
      );
  });
});
