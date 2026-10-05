// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;
import {LegacyBlocks} from "./LegacyBlocks.sol";
import {PreviousSpecs as HistoricalSpecs} from "./PreviousSpecs.sol";
import {Logs} from "../codec/Logs.sol";
import {Keys} from "../codec/Keys.sol";
// Frozen before adopting exact execute output allocation.
import {CommandBase} from "../commands/Base.sol";
import {DebitAccount} from "../commands/Debit.sol";
import {Execute} from "../codec/Execute.sol";
import {Encoder} from "../codec/Encoder.sol";
import {Sizes, Specs} from "../codec/Specs.sol";
import {DebitAccountHook} from "../core/Settlement.sol";
import {UnexpectedState} from "../utils/Errors.sol";

abstract contract PreviousOutputBootstrap is CommandBase, DebitAccountHook {
    uint private immutable id;

    constructor() {
        (id,) = command("bootstrap", Specs.Empty, HistoricalSpecs.Bootstrap, Specs.Balance, 0);
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
        (uint abs, uint end) = Execute.bounds(inputCur, 104);
        // floor(input.length / 104) * 72 <= input.length, so multiplication cannot overflow.
        uint cur;
        unchecked {
            (output, cur) = Encoder.init((end - abs) / 104 * Sizes.Balance);
        }
        credit = value;

        while (abs < end) {
            (bytes32 asset, uint amount, uint budget) = LegacyBlocks.unpackBootstrap(abs);
            credit = bootstrap(account, asset, amount, budget, credit);
            (output, cur) = Encoder.writeBalance(cur, output, asset, amount);
            unchecked {
                abs += 104;
            }
        }

        output = Encoder.finish(cur, output);
        return (true, output, credit);
    }
}

abstract contract PreviousOutputDebitAccount is DebitAccount {
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
        uint cur;
        (output, cur) = Encoder.init(end - abs);

        while (abs < end) {
            (bytes32 asset, uint amount) = Execute.unpackAssetAmount(abs);
            debitAccount(account, asset, amount);
            (output, cur) = Encoder.writeBalance(cur, output, asset, amount);
            unchecked {
                abs += Sizes.AssetAmount;
            }
        }

        output = Encoder.finish(cur, output);
        Logs.memWrap(debitAccountId(), Keys.Output, output);
        return (true, output, value);
    }
}
