// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

import {CommandBase, Specs} from "./Base.sol";
import {Blocks} from "../codec/Blocks.sol";
import {Sizes} from "../codec/Specs.sol";
import {Cursors} from "../utils/Cursors.sol";
import {DebitAccountHook} from "../core/Settlement.sol";
import {UnexpectedState} from "../utils/Errors.sol";

/// @title Bootstrap
/// @notice Pipeline-local command that atomically starts with BALANCE state and native-value budget.
abstract contract Bootstrap is CommandBase, DebitAccountHook {
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
    /// @param input BOOTSTRAP block stream.
    /// @param value Native value available to fund chain-asset balances.
    /// @return handled Always true because this helper executed the command.
    /// @return output One BALANCE block per BOOTSTRAP input.
    /// @return credit Sourced budget contributions plus unused assigned value.
    function executeBootstrap(
        bytes32 account,
        bytes memory state,
        bytes calldata input,
        uint value
    ) internal returns (bool handled, bytes memory output, uint credit) {
        if (state.length != 0) revert UnexpectedState();

        (uint abs, uint end) = Cursors.bounds(input, Sizes.Bootstrap);
        output = new bytes(input.length / Sizes.Bootstrap * Sizes.Balance);
        credit = value;
        uint i;

        while (abs < end) {
            (bytes32 asset, uint amount, uint budget) = Blocks.unpackBootstrap(abs);
            credit = bootstrap(account, asset, amount, budget, credit);
            Blocks.writeBalance(output, i, asset, amount);
            unchecked {
                abs += Sizes.Bootstrap;
                i += Sizes.Balance;
            }
        }

        return (true, output, credit);
    }
}
