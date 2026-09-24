// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

import {Execution, Executions, CommandBase, Specs} from "./Base.sol";
import {Position} from "../core/Types.sol";
import {Blocks, Memory} from "../codec/Blocks.sol";
import {Sizes} from "../codec/Specs.sol";

/// @notice Check each POSITION against a paired POSITION_LIMITS block and preserve the position.
/// @dev Checks identifiers and inclusive quantity bounds, not counterparty authorization or backing.
abstract contract CheckPosition is CommandBase {
    using Executions for Execution;

    uint private immutable descriptor;
    uint private immutable id;

    constructor() {
        (id, descriptor) = command("checkPosition", Specs.Position, Specs.PositionLimits, Specs.Position, 0);
    }

    /// @notice Return the registered checkPosition command ID.
    function checkPositionId() internal view returns (uint) {
        return id;
    }

    /// @notice Require matching assets, at least minAmount, and at most maxDebt.
    /// @param context Command context with one POSITION_LIMITS input per POSITION state block.
    /// @return Unchanged POSITION blocks.
    /// @return Zero native budget credit.
    function checkPosition(bytes calldata context) external onlyCommand returns (bytes memory, uint) {
        return runCommand(context, descriptor, checkPositionOne);
    }

    function checkPositionOne(Execution memory exec) private pure {
        Position memory position = exec.unpackPositionValue();
        exec.expectPositionLimits(position);
        exec.outputPosition(position);
    }
}

/// @notice Extends checkPosition with direct validation of memory-backed pipeline state.
abstract contract ExecuteCheckPosition is CheckPosition {
    // Literal Headers.Position / Headers.PositionLimits values for direct assembly use.
    uint private constant POSITION_HEADER = 0xe1f9db3d000000a0;
    uint private constant POSITION_LIMITS_HEADER = 0xd076068e00000080;

    // Right-aligned selectors for InvalidBlock(), UnexpectedValue(), and OutOfRange().
    uint private constant INVALID_BLOCK = 0xbe5a36cf;
    uint private constant UNEXPECTED_VALUE = 0x123146a6;
    uint private constant OUT_OF_RANGE = 0x7db3aba7;

    /// @notice Validate positions in place without unpacking or copying their blocks.
    /// @param state POSITION block stream in memory.
    /// @param input Exactly one calldata POSITION_LIMITS block per position.
    /// @param value Assigned native budget, returned unused.
    /// @return handled Always true.
    /// @return output The original state buffer, unchanged.
    /// @return credit Unused assigned native budget.
    function executeCheckPosition(
        bytes32,
        bytes memory state,
        bytes calldata input,
        uint value
    ) internal pure returns (bool handled, bytes memory output, uint credit) {
        (uint start, uint end) = Memory.bounds(state, Sizes.Position);
        if (input.length != (state.length / Sizes.Position) * Sizes.PositionLimits) revert Blocks.InvalidBlock();

        assembly ("memory-safe") {
            function fail(selector) {
                mstore(0, selector)
                revert(28, 4)
            }
            let q := input.offset
            // Strides include each block's eight-byte header.
            for {
                let p := start
            } lt(p, end) {
                p := add(p, 168)
                q := add(q, 136)
            } {
                if or(
                    iszero(eq(shr(192, mload(p)), POSITION_HEADER)),
                    iszero(eq(shr(192, calldataload(q)), POSITION_LIMITS_HEADER))
                ) {
                    fail(INVALID_BLOCK)
                }
                if or(
                    xor(mload(add(p, 0x08)), calldataload(add(q, 0x08))),
                    xor(mload(add(p, 0x48)), calldataload(add(q, 0x48)))
                ) {
                    fail(UNEXPECTED_VALUE)
                }
                if or(
                    lt(mload(add(p, 0x28)), calldataload(add(q, 0x28))),
                    gt(mload(add(p, 0x68)), calldataload(add(q, 0x68)))
                ) {
                    fail(OUT_OF_RANGE)
                }
            }
        }

        return (true, state, value);
    }
}
