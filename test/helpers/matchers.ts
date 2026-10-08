import { decodeEndpointLog } from "./endpoint-logs.js";
import { decodeMetadataLog } from "./metadata-logs.js";
import * as chai from "chai";
import type { BaseContract, ContractTransactionResponse, Log } from "ethers";
import { id } from "ethers";

function tryDecodeErrorName(contract: BaseContract, data: string): string | null {
  try {
    const decoded = contract.interface.parseError(data);
    return decoded?.name ?? null;
  } catch {
    return null;
  }
}

function extractFromMessage(message: string): string | null {
  if (!message) return null;
  const match =
    message.match(/custom error '(\w+)/i) ??
    message.match(/error "([^"]+)"/i) ??
    message.match(/revert\s+(\w+)/i);
  return match?.[1] ?? null;
}

function getErrorData(e: unknown): string | null {
  if (typeof e !== "object" || e === null) return null;
  const err = e as Record<string, unknown>;
  // Direct data field
  if (typeof err["data"] === "string") return err["data"];
  const rpcError = err["error"] as Record<string, unknown> | undefined;
  if (typeof rpcError?.["data"] === "string") return rpcError["data"];
  // Nested in e.info.error.data (Hardhat UNKNOWN_ERROR pattern)
  const info = err["info"] as Record<string, unknown> | undefined;
  const innerErr = info?.["error"] as Record<string, unknown> | undefined;
  if (typeof innerErr?.["data"] === "string") return innerErr["data"];
  return null;
}

function parseLog(contract: BaseContract, log: Log) {
  try {
    return contract.interface.parseLog({ topics: log.topics as string[], data: log.data });
  } catch {
    return null;
  }
}

type LogArgs = readonly unknown[];
type DecodeLog = (log: Log) => readonly LogArgs[];
type Transaction = ContractTransactionResponse | Promise<ContractTransactionResponse>;

function makeLogPromise(
  transaction: Transaction,
  contract: BaseContract,
  label: string,
  decoder: () => DecodeLog | Promise<DecodeLog>,
): Promise<void> & { withArgs(...args: unknown[]): Promise<void> } {
  const pending = Promise.resolve(transaction);
  pending.catch(() => {});

  const check = async (args: unknown[] = []) => {
    const receipt = await (await pending).wait();
    if (!receipt) throw new chai.AssertionError(`No receipt returned for '${label}'`);
    const address = (await contract.getAddress()).toLowerCase();
    const decode = await decoder();
    const records = receipt.logs
      .filter(log => log.address.toLowerCase() === address)
      .flatMap(log => decode(log));
    if (records.some(values => args.every((arg, i) =>
      arg === undefined || String(values[i]) === String(arg)))) return;
    throw new chai.AssertionError(
      `Expected '${label}' with args [${args.map(String)}]; found ${records.length} matching records`
      + (records.length ? `: ${records.map(values => "[" + values.map(String).join(", ") + "]").join(", ")}` : ""),
    );
  };

  return {
    withArgs: (...args: unknown[]) => check(args),
    then: (onFulfilled?: ((value: void) => unknown) | null, onRejected?: ((reason: unknown) => unknown) | null) =>
      check().then(onFulfilled, onRejected),
    catch: (onRejected?: ((reason: unknown) => unknown) | null) => check().catch(onRejected),
    finally: (onFinally?: (() => void) | null) => check().finally(onFinally ?? undefined),
  } as Promise<void> & { withArgs(...args: unknown[]): Promise<void> };
}

chai.use((chaiLib, utils) => {
  chaiLib.Assertion.addMethod(
    "revertedWithCustomError",
    function (this: object, contract: BaseContract, errorName: string) {
      const promise: Promise<unknown> = Promise.resolve(utils.flag(this, "object"));
      promise.catch(() => {});
      return promise.then(
        () => {
          throw new chai.AssertionError(
            `Expected transaction to revert with '${errorName}', but it succeeded`
          );
        },
        (e: unknown) => {
          const err = e as Record<string, unknown>;
          const revert = err["revert"] as Record<string, unknown> | undefined;
          const data = getErrorData(e);
          const actualName =
            (typeof err["errorName"] === "string" ? err["errorName"] : null) ??
            (typeof revert?.["name"] === "string" ? (revert["name"] as string) : null) ??
            (data ? tryDecodeErrorName(contract, data) : null) ??
            // Assembly-only reverts may be absent from the generated contract ABI.
            // Match the complete four-byte payload for parameterless errors.
            (data === id(errorName + "()").slice(0, 10) ? errorName : null) ??
            extractFromMessage(String(err["message"] ?? ""));
          if (actualName !== errorName) {
            throw new chai.AssertionError(
              `Expected revert with '${errorName}', but got '${actualName ?? String(err["message"])}'`
            );
          }
        }
      );
    }
  );

  chaiLib.Assertion.addMethod(
    "emitEndpoint",
    function (this: object, contract: BaseContract) {
      return makeLogPromise(utils.flag(this, "object"), contract, "ENDPOINT", () => log => {
        const values = decodeEndpointLog(log);
        return values ? [values] : [];
      });
    }
  );

  chaiLib.Assertion.addMethod(
    "emitMetadata",
    function (this: object, contract: BaseContract) {
      return makeLogPromise(utils.flag(this, "object"), contract, "METADATA", () => {
        return log => decodeMetadataLog(log).map(value => [value.entity, value.data]);
      });
    }
  );

  chaiLib.Assertion.addMethod(
    "emit",
    function (this: object, contract: BaseContract, eventName: string) {
      return makeLogPromise(utils.flag(this, "object"), contract, eventName, () => log => {
        const parsed = parseLog(contract, log);
        return parsed?.name === eventName ? [parsed.args] : [];
      });
    }
  );
});
