// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;
import {Logs as PreviousLogs} from "./PreviousEventLogs.sol";
import {Entities} from "./PreviousEntities.sol";
import {Actions} from "./PreviousActions.sol";

import {CommandBase, Specs} from "../commands/Base.sol";
import {Blocks} from "../codec/Blocks.sol";
import {Encoder} from "../codec/Encoder.sol";
import {Execute} from "../codec/Execute.sol";
import {Logs} from "../codec/Logs.sol";
import {Sizes} from "../codec/Specs.sol";
import {DebitAccountHook} from "../core/Settlement.sol";
import {UnexpectedState} from "../utils/Errors.sol";

/// @notice Pipeline-local balance funding with a minimum remaining native budget.
abstract contract BootstrapStock150 is CommandBase, DebitAccountHook {
    uint private immutable id;

    constructor() {
        (id, ) = command("bootstrap", Specs.Empty, Specs.Bootstrap, Specs.Balance, 0);
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
    /// Logs actual nonzero debits once with AccountBootstrap, in hook order.
    /// Reuses output until a native or zero request requires a separate log buffer.
    /// Account identity comes from pipeline context; no debits means no log.
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

        uint logStart = i;
        uint logCur; // Zero while the log still shares the output buffer.
        uint nativeAmount;
        while (abs < end) {
            (bytes32 asset, uint amount) = Execute.unpackAssetAmount(abs);
            if (asset != chainAsset && amount != 0) {
                debitAccount(account, asset, amount);
                if (logCur != 0) {
                    logCur = Encoder.writeBalanceAt(logCur, asset, amount);
                }
            } else {
                if (asset == chainAsset) nativeAmount += amount;
                if (logCur == 0) {
                    (logStart, logCur) = forkLog(output, i - logStart);
                }
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
            if (logCur == 0) (logStart, logCur) = forkLog(output, output.length);
            logCur = Encoder.writeBalanceAt(logCur, chainAsset, nativeAmount);
        }

        uint logSize = logCur == 0 ? output.length : logCur - logStart;
        if (logSize != 0) {
            PreviousLogs.mem((Entities.Account | (Actions.Bootstrap << 32)), logStart, logSize);
        }

        return (true, output, credit);
    }

    /// @dev Copy only the initialized output prefix. Reserve one block per request
    /// plus one combined native debit, so hook allocations cannot force growth.
    function forkLog(bytes memory output, uint prefixSize) private pure returns (uint start, uint cur) {
        bytes memory data = Encoder.allocate(output.length + Sizes.Balance);
        start = Encoder.pos(data, 0);
        cur = Encoder.copy(start, output, prefixSize);
    }
}
