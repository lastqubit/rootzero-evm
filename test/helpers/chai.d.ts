import type {BaseContract} from "ethers";

declare global {
  namespace Chai {
    interface Assertion {
      revertedWithCustomError(contract: BaseContract, errorName: string): Promise<void>;
      emitEndpoint(contract: BaseContract): Promise<void> & {withArgs(...args: unknown[]): Promise<void>};
      emitAnnotation(contract: BaseContract): Promise<void> & {withArgs(...args: unknown[]): Promise<void>};
      emit(
        contract: BaseContract,
        eventName: string,
      ): Promise<void> & {withArgs(...args: unknown[]): Promise<void>};
      above(value: number | Date | bigint, message?: string): Assertion;
      greaterThan(value: number | Date | bigint, message?: string): Assertion;
      gt(value: number | Date | bigint, message?: string): Assertion;
      least(value: number | Date | bigint, message?: string): Assertion;
      atLeast(value: number | Date | bigint, message?: string): Assertion;
      gte(value: number | Date | bigint, message?: string): Assertion;
      below(value: number | Date | bigint, message?: string): Assertion;
      lessThan(value: number | Date | bigint, message?: string): Assertion;
      lt(value: number | Date | bigint, message?: string): Assertion;
      most(value: number | Date | bigint, message?: string): Assertion;
      atMost(value: number | Date | bigint, message?: string): Assertion;
      lte(value: number | Date | bigint, message?: string): Assertion;
    }
  }
}

export {};
