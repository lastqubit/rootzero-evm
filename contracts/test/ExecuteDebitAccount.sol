// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

import {DebitAccount} from "../commands/Debit.sol";
import {Execute} from "../codec/Execute.sol";
import {Sizes} from "../codec/Specs.sol";
import {UnexpectedState} from "../utils/Errors.sol";

/// @title ExecuteDebitAccount
/// @notice Test-only pipeline adapter for `DebitAccount`, a source of BALANCE state in tests.
/// @dev This adapter is not a separate command. It uses the command ID and account hook
/// inherited from `DebitAccount` while decoding its fixed-stride input directly from calldata.
abstract contract ExecuteDebitAccount is DebitAccount {
    /// @notice Execute the inherited debit-account command from an internal pipeline.
    /// @param account Account whose funds are debited.
    /// @param state Empty pipeline state required by the command schema.
    /// @param inputCur ASSET_AMOUNT block stream.
    /// @param value Native value assigned to the command; returned unused as credit.
    /// @return handled Always true because this helper executed the command.
    /// @return output BALANCE block stream matching the debited amounts.
    /// @return credit Unused assigned native value.
    function executeDebitAccount(
        bytes32 account,
        bytes memory state,
        uint inputCur,
        uint value
    ) internal returns (bool handled, bytes memory output, uint credit) {
        if (state.length != 0) revert UnexpectedState();
        (uint abs, uint end) = Execute.bounds(inputCur, Sizes.AssetAmount);
        uint i;
        unchecked {
            (i, output) = Execute.allocateBalances((end - abs) / Sizes.AssetAmount);
        }

        while (abs < end) {
            (bytes32 asset, uint amount) = Execute.unpackAssetAmount(abs);
            debitAccount(account, asset, amount);
            i = Execute.writeBalance(i, asset, amount);
            unchecked {
                abs += Sizes.AssetAmount;
            }
        }

        return (true, output, value);
    }
}
