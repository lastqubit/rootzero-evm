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

function argsMatch(parsed: ReturnType<typeof parseLog>, args: unknown[]): boolean {
  if (!parsed) return false;
  for (let i = 0; i < args.length; i++) {
    if (args[i] === undefined) continue;
    const actual = parsed.args[i];
    if (actual?.toString() !== (args[i] as { toString(): string }).toString()) return false;
  }
  return true;
}

function makeEmitPromise(
  txPromise: Promise<ContractTransactionResponse> | ContractTransactionResponse,
  contract: BaseContract,
  eventName: string
): Promise<void> & { withArgs(...args: unknown[]): Promise<void> } {
  const guardedTxPromise = Promise.resolve(txPromise);
  guardedTxPromise.catch(() => {});

  const check = async (args?: unknown[]) => {
    const tx = await guardedTxPromise;
    const receipt = await tx.wait();
    if (!receipt) throw new chai.AssertionError(`No receipt returned for '${eventName}'`);

    if (args && args.length > 0) {
      // Find a log matching name AND args
      const found = receipt.logs.some((log) => {
        const parsed = parseLog(contract, log);
        return parsed?.name === eventName && argsMatch(parsed, args);
      });
      if (!found) {
        // Find any log with matching name for a better error message
        const nameMatch = receipt.logs.find((log) => parseLog(contract, log)?.name === eventName);
        if (nameMatch) {
          const parsed = parseLog(contract, nameMatch)!;
          const actualArgs = Array.from({ length: args.length }, (_, i) => parsed.args[i]?.toString());
          throw new chai.AssertionError(
            `Event '${eventName}' emitted but args don't match.\n  Expected: [${args.map(String)}]\n  Got:      [${actualArgs}]`
          );
        }
        throw new chai.AssertionError(`Expected event '${eventName}' to be emitted but it wasn't`);
      }
    } else {
      const found = receipt.logs.some((log) => parseLog(contract, log)?.name === eventName);
      if (!found) throw new chai.AssertionError(`Expected event '${eventName}' to be emitted but it wasn't`);
    }
  };

  const thenable = {
    withArgs: (...args: unknown[]) => check(args),
    then: (onFulfilled?: ((value: void) => unknown) | null, onRejected?: ((reason: unknown) => unknown) | null) =>
      check().then(onFulfilled, onRejected),
    catch: (onRejected?: ((reason: unknown) => unknown) | null) => check().catch(onRejected),
    finally: (onFinally?: (() => void) | null) => check().finally(onFinally ?? undefined),
  };

  return thenable as Promise<void> & { withArgs(...args: unknown[]): Promise<void> };
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
    "emit",
    function (this: object, contract: BaseContract, eventName: string) {
      const val: Promise<ContractTransactionResponse> | ContractTransactionResponse =
        utils.flag(this, "object");
      return makeEmitPromise(val, contract, eventName);
    }
  );
});


