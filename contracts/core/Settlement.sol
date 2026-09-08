// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

import {Accounts} from "../utils/Accounts.sol";
import {AmountOutOfRange} from "../utils/Errors.sol";

import {Limits, Position} from "./Types.sol";

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

/// @title PostHook
/// @notice Hook for posting one transaction between accounts.
abstract contract PostHook {
    /// @notice Override to post one transaction.
    /// @dev Returning successfully asserts that the complete transaction was posted.
    /// The hook must revert if it cannot apply the complete amount according to
    /// its account and zero-account policy.
    /// @param from Source account identifier, or zero when no debit side exists.
    /// @param to Destination account identifier, or zero when no credit side exists.
    /// @param asset Asset identifier.
    /// @param amount Exact amount to post.
    function post(bytes32 from, bytes32 to, bytes32 asset, uint amount) internal virtual;
}

/// @title BookHook
/// @notice Hook for applying a Rootzero-backed position to an account.
abstract contract BookHook {
    /// @notice Book a position's exact liability and asset amounts for `account`.
    /// @dev The command requires a zero counterparty. Successful return asserts
    /// that the full debt was debited and the full amount credited, or the hook
    /// must revert. No fees or source remainder are added by this operation.
    /// @param account Account whose position is booked.
    /// @param position Rootzero-backed position to apply completely.
    function book(bytes32 account, Position memory position) internal virtual;
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
/// @notice Default account-hook implementation for booking, transaction posting and position settlement.
abstract contract Settlement is PostHook, DebitAccountHook, CreditAccountHook, BookHook, SettleHook {
    /// @notice Post one transaction by debiting its source and crediting its destination.
    /// Returns without calling either hook when `amount` is zero and skips either
    /// operation when the corresponding account is zero.
    /// @param from Source account identifier, or zero to skip the debit.
    /// @param to Destination account identifier, or zero to skip the credit.
    /// @param asset Asset identifier.
    /// @param amount Exact amount to post.
    function post(bytes32 from, bytes32 to, bytes32 asset, uint amount) internal virtual override {
        if (amount == 0) return;
        if (from != 0) debitAccount(from, asset, amount);
        if (to != 0) creditAccount(to, asset, amount);
    }

    /// @notice Book a position by debiting its liability and crediting its asset.
    /// @dev The caller must require a zero counterparty. Zero amounts skip their
    /// respective account hooks. Any failure reverts both sides.
    /// @param account Account whose position is booked.
    /// @param position Rootzero-backed position with exact amounts.
    function book(bytes32 account, Position memory position) internal virtual override {
        if (position.debt != 0) debitAccount(account, position.liability, position.debt);
        if (position.amount != 0) creditAccount(account, position.asset, position.amount);
    }

    /// @notice Settle the liability from account to counterparty and the asset in the opposite direction.
    /// @dev Requires an account-category counterparty, rejecting zero.
    /// The trusted caller and account hooks remain responsible for authorization.
    /// This implementation adds no fees and checks both limits before account operations.
    /// @dev A successful return means the complete exact-net `debt` was satisfied.
    /// Skips either operation when its corresponding amount is zero, including position
    /// sides encoded as absent with a zero identifier and quantity.
    /// @param account Account whose position is settled.
    /// @param position Full position; the hook validates the counterparty and authorizes the exchange.
    /// @param limits Minimum net asset amount and maximum total debt, including fees; enforced by the hook.
    function settle(bytes32 account, Position memory position, Limits memory limits) internal virtual override {
        bytes32 counterparty = Accounts.account(position.counterparty);
        if (position.amount < limits.amount || position.debt > limits.debt) revert AmountOutOfRange();
        if (position.debt != 0) {
            debitAccount(account, position.liability, position.debt);
            creditAccount(counterparty, position.liability, position.debt);
        }
        if (position.amount != 0) {
            debitAccount(counterparty, position.asset, position.amount);
            creditAccount(account, position.asset, position.amount);
        }
    }
}
