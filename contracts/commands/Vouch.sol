// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

import {CommandBase, Specs} from "./Base.sol";
import {Encoder} from "../codec/Encoder.sol";
import {VOUCH_KEY, LIST_KEY} from "../codec/Keys.sol";
import {ENTITY_HEADER, TRUST_HEADER} from "../codec/Specs.sol";
import {DebitAccountHook} from "../core/Settlement.sol";
import {ROOTZERO_ASSET, TRUST_SALT, UNTRUSTED} from "../core/Trust.sol";
import {UnexpectedState, INVALID_BLOCK} from "../utils/Errors.sol";

/// @title ExecuteVouch
/// @notice Pipeline-local trust vouching with a minimum remaining native budget.
/// @dev Commander counterpart of ExecuteBootstrap: it starts a pipeline with TRUST state
/// for IDs in this host's trusted set instead of BALANCE state.
abstract contract ExecuteVouch is CommandBase, DebitAccountHook {
    uint private immutable id;

    constructor() {
        (id, ) = command("vouch", Specs.Empty, Specs.Vouch, Specs.Trust, 0);
    }

    /// @notice Return the registered VOUCH command ID.
    /// @return Registered command node identifier.
    function vouchId() internal view returns (uint) {
        return id;
    }

    /// @notice Execute exactly one VOUCH containing a budget and ENTITY list.
    /// @dev Rejects empty input and additional outer blocks. Allocates exactly one
    /// TRUST per inner item before checks run. Each ID must be in this host's trusted
    /// set, otherwise reverts `Untrusted(id)`; the chain and Rootzero assets always pass. When assigned value is below the
    /// budget, debits the shortfall from the account's chainAsset balance once.
    /// Balance-update logging belongs to the debit hook.
    /// @param account Account funding any native shortfall.
    /// @param state Must be empty.
    /// @param inputCur Validated calldata cursor over exactly one VOUCH block;
    /// higher metadata bits are ignored. Callers establish calldata provenance.
    /// @param value Assigned native value available for the budget.
    /// @return handled Always true.
    /// @return output Exactly one TRUST per requested ID, in input order.
    /// @return credit Assigned value, topped up to the requested budget.
    function executeVouch(
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
                    iszero(eq(shr(192, calldataload(abs)), or(shl(32, VOUCH_KEY), sub(length, 8)))),
                    iszero(eq(shr(192, calldataload(add(abs, 40))), or(shl(32, LIST_KEY), sub(length, 48))))
                ),
                mod(sub(length, 48), 40)
            ) {
                fail()
            }
            budget := calldataload(add(abs, 8))
            abs := add(abs, 48)
        }
        uint i;
        unchecked {
            // Reserve the complete output before any check can allocate memory.
            output = Encoder.allocate(end - abs);
            i = Encoder.pos(output, 0);
        }

        // Native assets are always trusted; other IDs read this host's Trust slot
        // (id ^ TRUST_SALT) directly.
        bytes32 chain = chainAsset;
        assembly ("memory-safe") {
            for {} lt(abs, end) { abs := add(abs, 40) } {
                if iszero(eq(shr(192, calldataload(abs)), ENTITY_HEADER)) {
                    mstore(0, INVALID_BLOCK)
                    revert(28, 4)
                }
                let entity := calldataload(add(abs, 8))
                if iszero(or(eq(entity, chain), eq(entity, ROOTZERO_ASSET))) {
                    if iszero(sload(xor(entity, TRUST_SALT))) {
                        mstore(0, shl(224, UNTRUSTED))
                        mstore(4, entity)
                        revert(0, 36)
                    }
                }
                mstore(i, shl(192, TRUST_HEADER))
                mstore(add(i, 8), entity)
                i := add(i, 40)
            }
        }

        credit = value;
        if (credit < budget) {
            debitAccount(account, chainAsset, budget - credit);
            credit = budget;
        }

        return (true, output, credit);
    }
}
