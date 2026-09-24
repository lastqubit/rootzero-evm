// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

import {Execution, Executions, CommandBase, Specs} from "./Base.sol";
import {Blocks, Memory} from "../codec/Blocks.sol";
import {Sizes} from "../codec/Specs.sol";

/// @notice Check each BALANCE amount against paired inclusive ASSET_LIMITS and preserve the balance.
/// @dev Checks asset identity and quantity, not authorization or backing.
abstract contract CheckBalance is CommandBase {
    using Executions for Execution;

    uint private immutable descriptor;
    uint private immutable id;

    constructor() {
        (id, descriptor) = command("checkBalance", Specs.Balance, Specs.AssetLimits, Specs.Balance, 0);
    }

    /// @notice Return the registered checkBalance command ID.
    function checkBalanceId() internal view returns (uint) {
        return id;
    }

    /// @notice Require the expected asset and minimum <= amount <= maximum for each balance.
    /// @param context Command context with one ASSET_LIMITS input per BALANCE state block.
    /// @return Unchanged BALANCE blocks.
    /// @return Zero native budget credit.
    function checkBalance(bytes calldata context) external onlyCommand returns (bytes memory, uint) {
        return runCommand(context, descriptor, checkBalanceOne);
    }

    function checkBalanceOne(Execution memory exec) private pure {
        (bytes32 asset, uint amount) = exec.unpackBalance();
        exec.expectAssetLimits(asset, amount);
        exec.outputBalance(asset, amount);
    }
}

/// @notice Extends checkBalance with direct validation of memory-backed pipeline state.
abstract contract ExecuteCheckBalance is CheckBalance {
    // Literal Headers.Balance / Headers.AssetLimits values for direct assembly use.
    uint private constant BALANCE_HEADER = 0x0e170e1400000040;
    uint private constant ASSET_LIMITS_HEADER = 0x673ca8e400000060;

    // Right-aligned selectors for InvalidBlock(), UnexpectedValue(), and OutOfRange().
    uint private constant INVALID_BLOCK = 0xbe5a36cf;
    uint private constant UNEXPECTED_VALUE = 0x123146a6;
    uint private constant OUT_OF_RANGE = 0x7db3aba7;

    /// @notice Validate balances in place without unpacking or copying their blocks.
    /// @param state BALANCE block stream in memory.
    /// @param input Exactly one calldata ASSET_LIMITS block per balance.
    /// @param value Assigned native budget, returned unused.
    /// @return handled Always true.
    /// @return output The original state buffer, unchanged.
    /// @return credit Unused assigned native budget.
    function executeCheckBalance(
        bytes32,
        bytes memory state,
        bytes calldata input,
        uint value
    ) internal pure returns (bool handled, bytes memory output, uint credit) {
        (uint start, uint end) = Memory.bounds(state, Sizes.Balance);
        if (input.length != (state.length / Sizes.Balance) * Sizes.AssetLimits) revert Blocks.InvalidBlock();

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
                p := add(p, 72)
                q := add(q, 104)
            } {
                if or(
                    iszero(eq(shr(192, mload(p)), BALANCE_HEADER)),
                    iszero(eq(shr(192, calldataload(q)), ASSET_LIMITS_HEADER))
                ) {
                    fail(INVALID_BLOCK)
                }
                if iszero(eq(mload(add(p, 0x08)), calldataload(add(q, 0x08)))) {
                    fail(UNEXPECTED_VALUE)
                }
                let amount := mload(add(p, 0x28))
                if or(lt(amount, calldataload(add(q, 0x28))), gt(amount, calldataload(add(q, 0x48)))) {
                    fail(OUT_OF_RANGE)
                }
            }
        }

        return (true, state, value);
    }
}
