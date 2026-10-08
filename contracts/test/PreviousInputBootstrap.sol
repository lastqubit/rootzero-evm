// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;
import {Logs as PreviousLogs} from "./PreviousEventLogs.sol";
import {Entities} from "./PreviousEntities.sol";
import {Actions} from "./PreviousActions.sol";

import {LogsBalance151} from "./LogsBalance151.sol";

import {CommandBase, Executions, Specs} from "../commands/Base.sol";
import {Blocks} from "../codec/Blocks.sol";
import {Execute} from "../codec/Execute.sol";
import {Keys} from "../codec/Keys.sol";
import {Logs} from "../codec/Logs.sol";
import {Sizes} from "../codec/Specs.sol";
import {DebitAccountHook} from "../core/Settlement.sol";
import {UnexpectedState} from "../utils/Errors.sol";

/// @notice Pipeline-local balance funding with a minimum remaining native budget.
// Frozen input-logging baseline for gas comparisons.
abstract contract PreviousInputBootstrap is CommandBase, DebitAccountHook {
    uint private constant INPUT = Specs.Bootstrap;

    uint private immutable id;

    constructor() {
        (id, ) = command("bootstrap", Specs.Empty, INPUT, Specs.Balance, Logs.Input);
    }

    /// @notice Return the registered BOOTSTRAP command ID.
    function bootstrapId() internal view returns (uint) {
        return id;
    }

    /// @notice Execute exactly one BOOTSTRAP containing a budget and ASSET_AMOUNT list.
    /// @dev Rejects empty input and additional outer blocks. Allocates exactly one
    /// BALANCE per inner item before hooks run. Assigned value funds chainAsset
    /// balances first. Non-chain assets debit during the loop; uncovered chainAsset
    /// balances and the remaining budget shortfall debit once after the loop.
    /// Logs INPUT once: non-chain amounts describe actual debits; chainAsset amounts
    /// and budget are requests only. A nonzero actual chainAsset debit is logged
    /// separately with AccountDebit. Account identity comes from pipeline context.
    /// The sum of requested chainAsset amounts must fit uint256.
    /// @param account Account funding balances and any native shortfall.
    /// @param state Must be empty.
    /// @param inputCur Cursor over exactly one BOOTSTRAP block.
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
        (uint budget, uint balancesCur) = Blocks.unpackBootstrapExact(inputCur);
        (uint abs, uint end) = Execute.bounds(balancesCur, Sizes.AssetAmount);
        uint i;
        unchecked {
            (i, output) = Execute.allocateBalances((end - abs) / Sizes.AssetAmount);
        }
        PreviousLogs.copyWrap(id, Keys.Input, inputCur);

        uint nativeAmount;
        while (abs < end) {
            (bytes32 asset, uint amount) = Execute.unpackAssetAmount(abs);
            if (asset == chainAsset) {
                nativeAmount += amount;
            } else if (amount != 0) {
                debitAccount(account, asset, amount);
            }
            i = Execute.writeBalance(i, asset, amount);
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
        if (nativeAmount != 0) {
            debitAccount(account, chainAsset, nativeAmount);
            LogsBalance151.balance(chainAsset, nativeAmount, (Entities.Account | (Actions.Debit << 32)));
        }

        return (true, output, credit);
    }
}
