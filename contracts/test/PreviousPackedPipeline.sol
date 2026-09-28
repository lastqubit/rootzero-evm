// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

import {CommandAccess} from "../core/Access.sol";
import {STEP_KEY, BYTES_KEY, CONTEXT_KEY, RELAY_KEY} from "../codec/Keys.sol";
import {InsufficientValue, UnexpectedState, INVALID_BLOCK, OUT_OF_BOUNDS} from "../utils/Errors.sol";
import {Flags} from "../utils/Flags.sol";

/// @notice Hook implemented by hosts that execute encoded step streams.
abstract contract PackedPipeHook {
    /// @notice Execute a bounded calldata STEP cursor and return its remaining native-value budget.
    /// @dev stepsCur uses absolute start/end lanes in bits 0-31/32-63. Callers
    /// establish calldata provenance. State remains an owned memory buffer.
    function pipe(
        bytes32 account,
        bytes memory state,
        uint stepsCur,
        uint budget
    ) internal virtual returns (uint remaining);
}

/// @notice Hook implemented by pipeline hosts that execute host-local commands.
abstract contract PackedExecuteHook {
    /// @notice Try to execute one command whose node ID targets the current host.
    /// @dev Implementations returning `handled = true` are responsible for
    /// authorizing the command. Return false without side effects to delegate to
    /// the trusted normal external entrypoint. Handoff commands must be delegated
    /// because this hook receives an ordinary input payload cursor without the continuation that
    /// Pipeline adds to the RELAY envelope. Implementations may revert instead.
    /// Input is a validated calldata payload cursor; state and output remain memory buffers.
    function execute(
        uint cmd,
        bytes32 account,
        bytes memory state,
        uint inputCur,
        uint value
    ) internal virtual returns (bool handled, bytes memory output, uint credit);
}

/// @title PreviousPackedPipeline
/// @notice Frozen packed-input pipeline baseline for cursor separation benchmarks.
/// @dev This gas-sensitive implementation intentionally inlines the command ID
/// layout and the CONTEXT, BYTES, and RELAY block encodings. Changes to command
/// selector, target, or flag placement, or to those block layouts, must update
/// the corresponding assembly and packed-cursor logic here.
abstract contract PreviousPackedPipeline is CommandAccess, PackedPipeHook, PackedExecuteHook {
    /// @dev Private pipeline cursor layout:
    /// bits 0-31 current STEP offset, 32-63 stream end,
    /// 64-95 command-input offset, 96-127 command-input exclusive end.
    /// Offsets and lengths start as uint32 values; adding two such values
    /// plus at most 80 cannot overflow uint256. Exact child consumption and
    /// end <= uint32(streamEnd) prove input and end fit their packed lanes.
    function takeStep(uint cursor) private pure returns (uint cmd, uint value, uint updated) {
        assembly ("memory-safe") {
            function fail(selector) {
                mstore(0, selector)
                revert(28, 4)
            }
            let abs := and(cursor, 0xffffffff)
            let head := calldataload(abs)
            if iszero(eq(shr(224, head), STEP_KEY)) {
                fail(INVALID_BLOCK)
            }
            let end := add(add(abs, 8), and(shr(192, head), 0xffffffff))
            cmd := calldataload(add(abs, 8))
            value := calldataload(add(abs, 40))
            head := calldataload(add(abs, 72))
            if iszero(eq(shr(224, head), BYTES_KEY)) {
                fail(INVALID_BLOCK)
            }
            let input := add(abs, 80)
            let size := and(shr(192, head), 0xffffffff)
            if iszero(eq(add(input, size), end)) {
                fail(INVALID_BLOCK)
            }
            if gt(end, and(shr(32, cursor), 0xffffffff)) {
                fail(OUT_OF_BOUNDS)
            }
            updated := or(or(end, and(cursor, 0xffffffff00000000)), or(shl(64, input), shl(96, end)))
        }
    }

    /// @dev Execute the prepared command call and strictly decode `(bytes, uint)`.
    /// `run` passes either a 64-bit input range cursor for ordinary calls,
    /// or the complete cursor for handoffs. A complete cursor always has a nonzero
    /// command-input offset in bits 64-95, even when that input is empty, because
    /// takeStep obtained it from a BYTES block inside the current calldata.
    function invokeCommand(
        bytes4 selector,
        address target,
        uint value,
        bytes32 account,
        bytes memory state,
        uint input
    ) private returns (bytes memory output, uint credit) {
        assembly ("memory-safe") {
            // Encode selector(bytes): ABI prefix, CONTEXT(account, state, input),
            // then zero padding. The allocation remains temporary until the call.
            function encodeCall(ptr, callSelector, activeAccount, stateBytes, inputCursor) -> size {
                let context := add(ptr, 0x44)
                let stateBlock := add(context, 40)
                let stateLength := mload(stateBytes)
                mstore(stateBlock, or(shl(224, BYTES_KEY), shl(192, stateLength)))
                mcopy(add(stateBlock, 8), add(stateBytes, 32), stateLength)
                let inputPtr := add(add(stateBlock, 8), stateLength)
                let end
                // Ordinary calls carry BYTES input; handoffs carry RELAY(input, remaining steps).
                switch iszero(shr(64, inputCursor))
                case 1 {
                    let inputLength := sub(and(shr(32, inputCursor), 0xffffffff), and(inputCursor, 0xffffffff))
                    mstore(inputPtr, or(shl(224, BYTES_KEY), shl(192, inputLength)))
                    calldatacopy(add(inputPtr, 8), and(inputCursor, 0xffffffff), inputLength)
                    end := add(add(inputPtr, 8), inputLength)
                }
                default {
                    let inputLength := sub(and(shr(96, inputCursor), 0xffffffff), and(shr(64, inputCursor), 0xffffffff))
                    let stepsOffset := and(inputCursor, 0xffffffff)
                    let stepsLength := sub(and(shr(32, inputCursor), 0xffffffff), stepsOffset)
                    let relayLength := add(16, add(inputLength, stepsLength))
                    mstore(inputPtr, or(shl(224, BYTES_KEY), shl(192, add(8, relayLength))))
                    mstore(add(inputPtr, 8), or(shl(224, RELAY_KEY), shl(192, relayLength)))
                    let inputBlock := add(inputPtr, 16)
                    mstore(inputBlock, or(shl(224, BYTES_KEY), shl(192, inputLength)))
                    calldatacopy(add(inputBlock, 8), and(shr(64, inputCursor), 0xffffffff), inputLength)
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
            let size := encodeCall(scratch, selector, account, state, input)
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
        uint cursor
    ) private returns (bytes memory output, uint credit, uint updated) {
        if (address(uint160(cmd)) == address(this)) {
            bool handled;
            (handled, output, credit) = execute(cmd, account, state, cursor >> 64, value);
            if (handled) return (output, credit, cursor);
        }
        (bytes4 selector, address target) = enforceCommand(cmd);
        bool handoff = uint8(cmd >> 224) & Flags.Handoff != 0;
        (output, credit) = invokeCommand(selector, target, value, account, state, handoff ? cursor : cursor >> 64);
        updated = handoff ? (cursor & ~uint(type(uint32).max)) | uint32(cursor >> 32) : cursor;
    }

    /// @notice Execute a STEP block stream through the pipeline.
    /// @dev Reverts with `UnexpectedState` if the final threaded state is non-empty.
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
        uint cursor = stepsCur;

        while (uint32(cursor) < uint32(cursor >> 32)) {
            uint cmd;
            uint value;
            (cmd, value, cursor) = takeStep(cursor);
            if (value > budget) revert InsufficientValue();
            unchecked {
                budget -= value;
            }
            (state, value, cursor) = run(cmd, account, state, value, cursor);
            assembly ("memory-safe") {
                let total := add(budget, value)
                if lt(total, budget) {
                    // Preserve Solidity Panic(0x11), including its ABI encoding.
                    mstore(0, shl(224, 0x4e487b71))
                    mstore(4, 0x11)
                    revert(0, 36)
                }
                budget := total
            }
        }

        if (state.length != 0) revert UnexpectedState();
        return budget;
    }
}
