// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

import {AmountOutOfRange, ZeroFee} from "../utils/Errors.sol";
import {Fees} from "../utils/Fees.sol";
import {Limits, Position} from "./Types.sol";
import {HostAccount} from "./Runtime.sol";

/// @title DebitAccountHook
/// @notice Hook for exactly debiting externally managed account funds.
abstract contract DebitAccountHook {
    /// @notice Override to debit exactly `amount` from externally managed `account` funds.
    /// @dev Returning successfully asserts that the complete amount was debited. The
    /// hook must revert if it cannot debit the exact amount. Internal bookkeeping fees
    /// must not reduce the amount made available to the consuming operation.
    /// @param account Source account identifier.
    /// @param asset Asset identifier.
    /// @param amount Exact amount to debit.
    function debitAccount(bytes32 account, bytes32 asset, uint amount) internal virtual;
}

/// @title CreditAccountHook
/// @notice Hook for crediting externally managed account funds.
abstract contract CreditAccountHook {
    /// @notice Override to credit externally managed funds to `account`.
    /// @dev Returning successfully asserts that the complete amount was credited.
    /// The hook must revert if it cannot credit the complete amount.
    /// @param account Destination account identifier.
    /// @param asset Asset identifier.
    /// @param amount Exact amount to credit.
    function creditAccount(bytes32 account, bytes32 asset, uint amount) internal virtual;
}

/// @title BookHook
/// @notice Hook for applying one exact liability debit and one exact asset credit.
abstract contract BookHook {
    /// @notice Debit `debt` from `from`, then credit `amount` to `to`.
    /// @dev Apply both exact legs or revert. Zero amounts skip their legs; a zero
    /// account alone does not skip a nonzero leg. Callers define account policy,
    /// validate counterparties, and enforce limits and fees. Preserve debit-first
    /// funding requirements even when accounts or assets match; do not net the legs.
    /// @param from Account debited for the liability.
    /// @param to Account credited with the asset.
    /// @param asset Asset identifier for the credit.
    /// @param amount Exact quantity to credit.
    /// @param liability Asset identifier for the debit.
    /// @param debt Exact quantity to debit.
    function book(bytes32 from, bytes32 to, bytes32 asset, uint amount, bytes32 liability, uint debt) internal virtual;
}

/// @title SettleHook
/// @notice Hook for fully settling one asset-liability position.
abstract contract SettleHook {
    /// @notice Override to settle one position for `account`.
    /// @dev Returning successfully asserts that the complete exact-net `debt` was
    /// satisfied. Partial fulfillment is invalid because the consuming command emits
    /// no debt remainder. Revert if the complete quantity cannot be satisfied. Fees
    /// and sourcing costs must be paid in addition to, and must not reduce, `debt`.
    /// @param account Account whose position is settled.
    /// @param position Full position; the hook validates the counterparty and authorizes the exchange.
    /// @param limits Minimum net asset amount and maximum total debt, including fees; enforced by the hook.
    function settle(bytes32 account, Position memory position, Limits memory limits) internal virtual;
}

/// @title Settlement
/// @notice Default application of debit/credit legs plus reusable settlement mechanics.
/// @dev Intended for hosts that maintain account balances. Hosts without their own
/// balance ledger implement RealizeHook instead; a production host chooses one
/// position-fulfillment model. Hosts implement SettleHook themselves and choose
/// their fee policy; this contract inherits SettleHook without implementing it.
abstract contract Settlement is HostAccount, DebitAccountHook, CreditAccountHook, BookHook, SettleHook {
    /// @notice Apply exact legs through the account hooks, debiting before crediting.
    /// @dev Zero amounts skip their hooks. Matching accounts or assets are not
    /// netted: the full debit must succeed before the credit. Failure reverts both.
    function book(
        bytes32 from,
        bytes32 to,
        bytes32 asset,
        uint amount,
        bytes32 liability,
        uint debt
    ) internal virtual override {
        if (debt != 0) debitAccount(from, liability, debt);
        if (amount != 0) creditAccount(to, asset, amount);
    }

    /// @notice Repay exact debt and collect a surcharge when it fits the limit.
    /// @dev The caller validates the counterparty and authorizes the position.
    /// Call collect afterward with the returned bps to enforce any pending fee.
    /// Zero debt returns immediately;
    /// nonzero debt is checked against the limit before account operations. Failed account
    /// operations revert repayment and fee collection together.
    /// @param account Account paying the debt and fee.
    /// @param counterparty Account receiving the exact debt.
    /// @param liability Asset used to repay the debt and pay the fee.
    /// @param debt Exact quantity owed to the counterparty.
    /// @param bps Surcharge rate applied to the debt.
    /// @param limit Inclusive maximum total debit, including the fee.
    /// @return remainingBps Zero after collecting a nonzero fee, otherwise the input bps.
    function repay(
        bytes32 account,
        bytes32 counterparty,
        bytes32 liability,
        uint debt,
        uint16 bps,
        uint limit
    ) internal returns (uint16 remainingBps) {
        if (debt == 0) return bps;
        if (debt > limit) revert AmountOutOfRange();
        uint fee = Fees.addable(debt, bps, limit);
        bool combined = counterparty == hostAccount;
        book(account, counterparty, liability, combined ? debt + fee : debt, liability, debt + fee);
        if (fee != 0 && !combined) creditAccount(hostAccount, liability, fee);
        return fee == 0 ? bps : 0;
    }

    /// @notice Collect the asset amount and any fee left pending by repayment.
    /// @dev The caller validates the counterparty and authorizes the position.
    /// Call after repay, passing its returned bps to complete fee enforcement.
    /// Checks the base asset limit before
    /// the zero-amount return or account operations. Failed account
    /// operations revert collection and fee payment together.
    /// When the counterparty receives the fee, only the net amount is debited;
    /// account hooks must support this net transfer rather than require gross flows.
    /// Reverts with ZeroFee before transfers if nonzero bps yields no fee,
    /// including when the asset amount is zero.
    /// @param account Account receiving the asset amount after the fee.
    /// @param counterparty Account providing the full asset amount.
    /// @param asset Asset being collected and used to pay the fee.
    /// @param amount Full quantity provided by the counterparty.
    /// @param bps Remaining fee rate from repay; zero means no further fee is required.
    /// @param limit Inclusive minimum net amount credited to the account.
    function collect(
        bytes32 account,
        bytes32 counterparty,
        bytes32 asset,
        uint amount,
        uint16 bps,
        uint limit
    ) internal {
        if (amount < limit) revert AmountOutOfRange();
        uint fee = Fees.deductible(amount, bps, limit);
        if (bps != 0 && fee == 0) revert ZeroFee();
        if (amount == 0) return;
        bool combined = counterparty == hostAccount;
        uint net = amount - fee;
        uint debit = combined ? net : amount;
        book(counterparty, account, asset, net, asset, debit);
        if (fee != 0 && !combined) creditAccount(hostAccount, asset, fee);
    }
}
