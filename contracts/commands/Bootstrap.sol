// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

import {CommandBase, Specs} from "./Base.sol";
import {Execute} from "../codec/Execute.sol";
import {Sizes} from "../codec/Specs.sol";
import {DebitAccountHook} from "../core/Settlement.sol";
import {UnexpectedState} from "../utils/Errors.sol";

/// @title ExecuteBootstrap
/// @notice Pipeline-local command that atomically starts with BALANCE state and native-value budget.
abstract contract ExecuteBootstrap is CommandBase, DebitAccountHook {
    uint private immutable id;

    constructor() {
        (id,) = command("bootstrap", Specs.Empty, Specs.Bootstrap, Specs.Balance, 0);
    }

    /// @notice Return the registered BOOTSTRAP command ID.
    function bootstrapId() internal view returns (uint) {
        return id;
    }

    /// @dev Bootstrap one local balance, using assigned value before debiting
    /// any remaining chain-asset amount from the account.
    function bootstrap(
        bytes32 account,
        bytes32 asset,
        uint amount,
        uint budget,
        uint value
    ) private returns (uint) {
        if (asset == chainAsset) {
            uint funded = amount < value ? amount : value;
            unchecked {
                amount -= funded;
                value -= funded;
            }
            amount += budget;
        } else {
            if (amount != 0) debitAccount(account, asset, amount);
            amount = budget;
        }

        if (amount != 0) debitAccount(account, chainAsset, amount);
        return value + budget;
    }

    /// @notice Execute bootstrap directly against a calldata BOOTSTRAP stream.
    /// @param account Account funding the pipeline.
    /// @param state Empty pipeline state required by the command schema.
    /// @param inputCur Cursor over BOOTSTRAP block stream.
    /// @param value Native value available to fund chain-asset balances.
    /// @return handled Always true because this helper executed the command.
    /// @return output One BALANCE block per BOOTSTRAP input.
    /// @return credit Sourced budget contributions plus unused assigned value.
    function executeBootstrap(
        bytes32 account,
        bytes memory state,
        uint inputCur,
        uint value
    ) internal returns (bool handled, bytes memory output, uint credit) {
        if (state.length != 0) revert UnexpectedState();
        (uint abs, uint end) = Execute.bounds(inputCur, Sizes.Bootstrap);
        uint i;
        unchecked {
            (i, output) = Execute.allocateBalances((end - abs) / Sizes.Bootstrap);
        }
        credit = value;

        while (abs < end) {
            (bytes32 asset, uint amount, uint budget) = Execute.unpackBootstrap(abs);
            credit = bootstrap(account, asset, amount, budget, credit);
            i = Execute.writeBalance(i, asset, amount);
            unchecked {
                abs += Sizes.Bootstrap;
            }
        }

        return (true, output, credit);
    }
}
