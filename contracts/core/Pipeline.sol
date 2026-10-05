// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

import {CommandAccess} from "./Access.sol";
import {STEP_KEY, STATE_KEY, INPUT_KEY, BYTES_KEY, CONTEXT_KEY, RELAY_KEY} from "../codec/Keys.sol";
import {InsufficientValue, UnexpectedState, INVALID_BLOCK, OUT_OF_BOUNDS} from "../utils/Errors.sol";
import {Logs} from "../codec/Logs.sol";
import {Entities} from "../utils/Entities.sol";
import {Cursors} from "../utils/Cursors.sol";
import {Flags} from "../utils/Flags.sol";

/// @notice Hook implemented by hosts that execute encoded step streams.
abstract contract PipeHook {
    /// @notice Execute a bounded calldata STEP cursor and return its remaining native-value budget.
    /// @dev stepsCur uses absolute start/end lanes in bits 0-31/32-63. Callers
    /// establish calldata provenance and supply an account satisfying their policy.
    /// Account format is trusted internally. State remains an owned memory buffer.
    /// @param account Account used for each dispatched command.
    /// @param state Initial state block stream threaded through the steps.
    /// @param stepsCur Bounded calldata cursor over the STEP block stream.
    /// @param budget Native value available to execute the steps, in wei.
    /// @return remaining Unspent native value for the caller to settle, in wei.
    function pipe(
        bytes32 account,
        bytes memory state,
        uint stepsCur,
        uint budget
    ) internal virtual returns (uint remaining);
}

/// @notice Hook implemented by pipeline hosts that execute host-local commands.
abstract contract ExecuteHook {
    /// @notice Try to execute one command whose node ID targets the current host.
    /// @dev Implementations returning `handled = true` are responsible for
    /// authorizing the command. Return false without side effects to delegate to
    /// the trusted normal external entrypoint. Handoff commands must be delegated
    /// because this hook receives an ordinary input payload cursor without the continuation that
    /// Pipeline adds to the RELAY envelope. Implementations may revert instead.
    /// Input is a structurally validated calldata payload cursor; state and output
    /// remain memory buffers. Account format is trusted from the caller, but command
    /// authorization does not validate account IDs in untrusted command input.
    /// @param cmd Host-local command node ID to authorize and execute.
    /// @param account Account supplied to the command.
    /// @param state State block stream supplied to the command.
    /// @param inputCur Bounded calldata cursor over command input, excluding the BYTES header.
    /// @param value Native value assigned to this command, in wei.
    /// @return handled Whether the hook executed the command instead of delegating it.
    /// @return output Resulting state block stream; ignored when handled is false.
    /// @return credit Native value returned to the pipeline budget, in wei; ignored when handled is false.
    function execute(
        uint cmd,
        bytes32 account,
        bytes memory state,
        uint inputCur,
        uint value
    ) internal virtual returns (bool handled, bytes memory output, uint credit);
}

/// @title Pipeline
/// @notice Core pipeline functionality shared by higher-level surfaces.
/// @dev This gas-sensitive implementation intentionally inlines the command ID
/// layout and the CONTEXT, STATE, INPUT, BYTES, and RELAY block encodings. Changes to command
/// selector, target, or flag placement, or to those block layouts, must update
/// the corresponding assembly and packed-cursor logic here.
abstract contract Pipeline is CommandAccess, PipeHook, ExecuteHook {
    /// @dev Decode one STEP into its command, value, clean input cursor, and
    /// advanced stream cursor. Both cursors use standard absolute start/end lanes.
    /// The exact child end and stream bound prove both cursors fit uint32 lanes.
    function takeStep(uint cur) private pure returns (uint cmd, uint value, uint inputCur, uint nextCur) {
        assembly ("memory-safe") {
            function fail(selector) {
                mstore(0, selector)
                revert(28, 4)
            }
            let abs := and(cur, 0xffffffff)
            let head := calldataload(abs)
            if iszero(eq(shr(224, head), STEP_KEY)) {
                fail(INVALID_BLOCK)
            }
            let end := add(add(abs, 8), and(shr(192, head), 0xffffffff))
            cmd := calldataload(add(abs, 8))
            value := calldataload(add(abs, 40))
            head := calldataload(add(abs, 72))
            if iszero(eq(shr(224, head), INPUT_KEY)) {
                fail(INVALID_BLOCK)
            }
            let input := add(abs, 80)
            let size := and(shr(192, head), 0xffffffff)
            if iszero(eq(add(input, size), end)) {
                fail(INVALID_BLOCK)
            }
            if gt(end, and(shr(32, cur), 0xffffffff)) {
                fail(OUT_OF_BOUNDS)
            }
            inputCur := or(input, shl(32, end))
            nextCur := or(end, and(cur, not(0xffffffff)))
        }
    }

    /// @dev Authorize and invoke a command, strictly decoding (bytes, uint).
    /// Handoffs receive the remaining STEP stream and exhaust the returned cursor;
    /// ordinary calls receive only inputCur and preserve the remaining cursor.
    function invokeCommand(
        uint cmd,
        bytes32 account,
        bytes memory state,
        uint value,
        uint inputCur,
        uint stepsCur
    ) private returns (bytes memory output, uint credit, uint nextCur) {
        (bytes4 selector, address target) = enforceCommand(cmd);
        if (uint8(cmd >> 224) & Flags.Handoff != 0) {
            nextCur = Cursors.exhaust(stepsCur);
        } else {
            nextCur = stepsCur;
            stepsCur = 0;
        }

        assembly ("memory-safe") {
            // Encode selector(bytes): ABI prefix, CONTEXT(account, state, input),
            // then zero padding. The allocation remains temporary until the call.
            function encodeCall(ptr, callSelector, activeAccount, stateBytes, inputCursor, stepsCursor) -> size {
                let context := add(ptr, 0x44)
                let stateBlock := add(context, 40)
                let stateLength := mload(stateBytes)
                mstore(stateBlock, or(shl(224, STATE_KEY), shl(192, stateLength)))
                mcopy(add(stateBlock, 8), add(stateBytes, 32), stateLength)
                let inputPtr := add(add(stateBlock, 8), stateLength)
                let end
                let inputAbs := and(inputCursor, 0xffffffff)
                let inputLength := sub(and(shr(32, inputCursor), 0xffffffff), inputAbs)
                // Ordinary calls carry INPUT; handoffs carry RELAY(input, remaining steps).
                switch iszero(stepsCursor)
                case 1 {
                    mstore(inputPtr, or(shl(224, INPUT_KEY), shl(192, inputLength)))
                    calldatacopy(add(inputPtr, 8), inputAbs, inputLength)
                    end := add(add(inputPtr, 8), inputLength)
                }
                default {
                    let stepsOffset := and(stepsCursor, 0xffffffff)
                    let stepsLength := sub(and(shr(32, stepsCursor), 0xffffffff), stepsOffset)
                    let relayLength := add(16, add(inputLength, stepsLength))
                    mstore(inputPtr, or(shl(224, INPUT_KEY), shl(192, add(8, relayLength))))
                    mstore(add(inputPtr, 8), or(shl(224, RELAY_KEY), shl(192, relayLength)))
                    let inputBlock := add(inputPtr, 16)
                    mstore(inputBlock, or(shl(224, INPUT_KEY), shl(192, inputLength)))
                    calldatacopy(add(inputBlock, 8), inputAbs, inputLength)
                    let stepsBlock := add(add(inputBlock, 8), inputLength)
                    mstore(stepsBlock, or(shl(224, BYTES_KEY), shl(192, stepsLength)))
                    calldatacopy(add(stepsBlock, 8), stepsOffset, stepsLength)
                    end := add(add(stepsBlock, 8), stepsLength)
                }
                let contextLength := sub(end, context)
                mstore(context, or(shl(224, CONTEXT_KEY), shl(192, sub(contextLength, 8))))
                mstore(add(context, 8), activeAccount)
                mstore(ptr, callSelector)
                mstore(add(ptr, 4), 32)
                mstore(add(ptr, 36), contextLength)
                // Scratch memory may be dirty, including the final ABI padding.
                mstore(end, 0)
                size := add(68, and(add(contextLength, 31), not(31)))
            }

            // Preserve the failing endpoint and its complete revert data.
            function revertCall(ptr, callTarget, callSelector) {
                let length := returndatasize()
                mstore(ptr, shl(224, 0x20577b07)) // FailedCall(address,bytes4,bytes)
                mstore(add(ptr, 4), callTarget)
                mstore(add(ptr, 36), shl(224, shr(224, callSelector)))
                mstore(add(ptr, 68), 96)
                mstore(add(ptr, 100), length)
                mstore(add(add(ptr, 132), length), 0)
                returndatacopy(add(ptr, 132), 0, length)
                revert(ptr, add(132, and(add(length, 31), not(31))))
            }

            // Strictly decode (bytes, uint), reusing the call's scratch space.
            // Only returndata survives; temporary call input is free to be reused.
            function decodeResult(ptr) -> result, returnedCredit {
                let length := returndatasize()
                if lt(length, 96) {
                    revert(0, 0)
                }
                returndatacopy(ptr, 0, length)
                if iszero(eq(mload(ptr), 64)) {
                    revert(0, 0)
                }
                let stateLength := mload(add(ptr, 64))
                if gt(stateLength, sub(length, 96)) {
                    revert(0, 0)
                }
                let paddedLength := and(add(stateLength, 31), not(31))
                if iszero(eq(length, add(96, paddedLength))) {
                    revert(0, 0)
                }
                result := add(ptr, 64)
                returnedCredit := mload(add(ptr, 32))
                mstore(0x40, and(add(add(ptr, length), 31), not(31)))
            }

            let scratch := mload(0x40)
            let size := encodeCall(scratch, selector, account, state, inputCur, stepsCur)
            let callTarget := and(target, 0xffffffffffffffffffffffffffffffffffffffff)
            if iszero(call(gas(), callTarget, value, scratch, size, 0, 0)) {
                revertCall(scratch, callTarget, selector)
            }
            output,credit := decodeResult(scratch)
        }
    }

    function run(
        uint cmd,
        bytes32 account,
        bytes memory state,
        uint value,
        uint inputCur,
        uint cur
    ) private returns (bytes memory output, uint credit, uint nextCur) {
        if (address(uint160(cmd)) == address(this)) {
            bool handled;
            (handled, output, credit) = execute(cmd, account, state, inputCur, value);
            if (handled) return (output, credit, cur);
        }
        return invokeCommand(cmd, account, state, value, inputCur, cur);
    }

    /// @notice Execute a STEP block stream through the pipeline.
    /// @dev Reverts with `UnexpectedState` if the final threaded state is non-empty.
    /// Emits account context and initial budget before any step, including empty pipelines.
    /// Callers remain responsible for settling the returned unspent value.
    /// @param account Account identifier used for each dispatched step.
    /// @param state Initial state block stream passed to the first step.
    /// @param stepsCur Bounded calldata cursor over the STEP stream to execute.
    /// @param budget Native-value budget shared across all steps.
    /// @return remaining Native value remaining after every step executes.
    function pipe(
        bytes32 account,
        bytes memory state,
        uint stepsCur,
        uint budget
    ) internal virtual override returns (uint remaining) {
        Logs.pipeline(account, budget, Entities.Account);
        while (Cursors.more(stepsCur)) {
            uint cmd;
            uint value;
            uint inputCur;
            (cmd, value, inputCur, stepsCur) = takeStep(stepsCur);
            if (value > budget) revert InsufficientValue();
            unchecked {
                budget -= value;
            }
            (state, value, stepsCur) = run(cmd, account, state, value, inputCur, stepsCur);
            budget += value;
        }

        if (state.length != 0) revert UnexpectedState();
        return budget;
    }
}
