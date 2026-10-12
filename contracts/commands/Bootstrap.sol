// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

import {CommandBase, Specs} from "./Base.sol";
import {Encoder} from "../codec/Encoder.sol";
import {BOOTSTRAP_KEY, LIST_KEY} from "../codec/Keys.sol";
import {Sizes, ASSET_AMOUNT_HEADER, BALANCE_HEADER} from "../codec/Specs.sol";
import {DebitAccountHook} from "../core/Settlement.sol";
import {UnexpectedState, INVALID_BLOCK} from "../utils/Errors.sol";

/// @title ExecuteBootstrap
/// @notice Pipeline-local balance funding with a minimum remaining native budget.
abstract contract ExecuteBootstrap is CommandBase, DebitAccountHook {
    uint private immutable id;

    constructor() {
        (id, ) = command("bootstrap", Specs.Empty, Specs.Bootstrap, Specs.Balance, 0);
    }

    /// @notice Return the registered BOOTSTRAP command ID.
    /// @return Registered command node identifier.
    function bootstrapId() internal view returns (uint) {
        return id;
    }

    /// @notice Execute exactly one BOOTSTRAP containing a budget and ASSET_AMOUNT list.
    /// @dev Rejects empty input and additional outer blocks. Allocates exactly one
    /// BALANCE per inner item before hooks run. Assigned value funds chainAsset
    /// balances first. Non-chain assets debit during the loop; uncovered chainAsset
    /// balances and the remaining budget shortfall debit once after the loop.
    /// Zero amounts skip debit hooks. Balance-update logging belongs to those hooks.
    /// The sum of requested chainAsset amounts must fit uint256.
    /// @param account Account funding balances and any native shortfall.
    /// @param state Must be empty.
    /// @param inputCur Validated calldata cursor over exactly one BOOTSTRAP block;
    /// higher metadata bits are ignored. Callers establish calldata provenance.
    /// @param value Assigned native value available for balances and budget.
    /// @return handled Always true.
    /// @return output Exactly one BALANCE per requested asset, in input order.
    /// @return credit Remaining assigned value, topped up to the requested budget.
    function executeBootstrap(
        bytes32 account,
        bytes memory state,
        uint inputCur,
        uint value
    ) internal returns (bool handled, bytes memory output, uint credit) {
        if (state.length != 0) revert UnexpectedState();
        uint abs = uint32(inputCur);
        uint end = uint32(inputCur >> 32);
        uint budget;
        // uint32 bounds cannot overflow these full-width additions. One check
        // rejects reversed/short ranges before subtraction; exact headers then
        // prove parent and LIST containment. Each item is checked in the loop.
        assembly ("memory-safe") {
            function fail() {
                mstore(0, INVALID_BLOCK)
                revert(28, 4)
            }
            if lt(end, add(abs, 48)) {
                fail()
            }
            let length := sub(end, abs)
            if or(
                or(
                    iszero(eq(shr(192, calldataload(abs)), or(shl(32, BOOTSTRAP_KEY), sub(length, 8)))),
                    iszero(eq(shr(192, calldataload(add(abs, 40))), or(shl(32, LIST_KEY), sub(length, 48))))
                ),
                mod(sub(length, 48), 72)
            ) {
                fail()
            }
            budget := calldataload(add(abs, 8))
            abs := add(abs, 48)
        }
        uint i;
        unchecked {
            // Reserve the complete output before hooks can allocate memory.
            output = Encoder.allocate(end - abs);
            i = Encoder.pos(output, 0);
        }

        uint nativeAmount;
        while (abs < end) {
            bytes32 asset;
            uint amount;
            assembly ("memory-safe") {
                if iszero(eq(shr(192, calldataload(abs)), ASSET_AMOUNT_HEADER)) {
                    mstore(0, INVALID_BLOCK)
                    revert(28, 4)
                }
                asset := calldataload(add(abs, 8))
                amount := calldataload(add(abs, 40))
            }
            if (asset != chainAsset) {
                if (amount != 0) debitAccount(account, asset, amount);
            } else {
                nativeAmount += amount;
            }
            assembly ("memory-safe") {
                mstore(i, shl(192, BALANCE_HEADER))
                mstore(add(i, 8), asset)
                mstore(add(i, 40), amount)
                i := add(i, 72)
            }
            unchecked {
                abs += Sizes.AssetAmount;
            }
        }

        uint funded = nativeAmount < value ? nativeAmount : value;
        credit = value - funded;
        nativeAmount -= funded;
        if (credit < budget) {
            nativeAmount += budget - credit;
            credit = budget;
        }
        if (nativeAmount != 0) debitAccount(account, chainAsset, nativeAmount);

        return (true, output, credit);
    }
}
