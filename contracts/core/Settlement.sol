// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

import {Booking, Position} from "./Types.sol";

/// @title DebitAccountHook
/// @notice Hook for exactly debiting externally managed account funds.
abstract contract DebitAccountHook {
    /// @notice Override to debit exactly `amount` from externally managed `account` funds.
    /// @dev Returning successfully asserts that the complete amount was debited. The
    /// hook must revert if it cannot debit the exact amount. Internal bookkeeping fees
    /// must not reduce the amount made available to the consuming operation.
    /// May assume account format satisfies the caller's policy without repeated
    /// format validation. Applicable authorization and balance checks remain.
    /// Emit Logs.balance(account, asset, updatedBalance) after a successful
    /// nonzero debit, including an updated balance of zero. Emission is the
    /// implementer's responsibility; reuse the mutation's result without rereading
    /// storage. Zero-amount calls should not emit unchanged balances.
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
    /// May assume account format satisfies the caller's policy without repeated
    /// format validation. Applicable authorization and accounting requirements remain.
    /// Emit Logs.balance(account, asset, updatedBalance) after a successful
    /// nonzero credit. Emission is the implementer's responsibility; reuse the
    /// mutation's result without rereading storage. Zero-amount calls should not
    /// emit unchanged balances.
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
    /// enforce limits and fees, and validate untrusted accounts at entry. Internal
    /// hooks may assume accounts satisfy that policy. Preserve debit-first
    /// funding requirements even when accounts or assets match; do not net the legs.
    /// @param value Exact debit and credit legs; hooks must not mutate this value.
    function book(Booking memory value) internal virtual;
}

/// @title RepayHook
/// @notice Hook for settling only the debt of a position.
abstract contract RepayHook {
    /// @notice Override to repay one position's debt for `account`.
    /// @dev Returning successfully asserts that the complete final `debt` was
    /// satisfied. Partial fulfillment is invalid because the consuming command
    /// clears debt in its output. Producers handle fees before creating the
    /// position: `debt` is the final total payment. Producers enforce limits before
    /// emitting positions. Apply the debt exactly, without extra fees, and leave
    /// the asset leg untouched. Do not mutate the position; the caller clears debt.
    /// @param account Account whose position debt is repaid.
    /// @param position Full position with trusted account format; the hook applies repayment authorization.
    function repay(bytes32 account, Position memory position) internal virtual;
}

/// @title SettleHook
/// @notice Hook for fully settling one asset-liability position.
abstract contract SettleHook {
    /// @notice Override to settle one position for `account`.
    /// @dev Returning successfully asserts that the complete final `debt` was
    /// satisfied. Partial fulfillment is invalid because the consuming command emits
    /// no debt remainder. Producers handle fees before creating the position:
    /// `amount` is the final net receipt and `debt` the final total payment.
    /// Producers enforce limits before emitting positions. Apply both quantities exactly, without extra fees.
    /// @param account Account whose position is settled.
    /// @param position Full position with trusted account format; the hook applies exchange authorization.
    function settle(bytes32 account, Position memory position) internal virtual;
}

/// @title Settlement
/// @notice Default application of debit/credit legs plus reusable settlement mechanics.
/// @dev Intended for hosts that maintain account balances. Hosts without their own
/// balance ledger implement RealizeHook instead; a production host chooses one
/// position-fulfillment model. Producers supply final quantities with fees already handled.
/// Trusted position producers and account hooks remain responsible for authorization.
abstract contract Settlement is DebitAccountHook, CreditAccountHook, BookHook, RepayHook, SettleHook {
    /// @notice Apply exact legs through the account hooks, debiting before crediting.
    /// @dev Zero amounts skip their hooks. Matching accounts or assets are not
    /// netted: the full debit must succeed before the credit. Failure reverts both.
    /// Override the scalar overload to customize both scalar and struct callers.
    function book(Booking memory value) internal virtual override {
        book(value.from, value.to, value.liability, value.debt, value.asset, value.amount);
    }

    /// @notice Apply exact scalar legs without constructing a temporary Booking.
    /// @dev Shared customization point for Settlement's scalar callers and struct wrapper.
    /// Overriding only book(Booking) does not intercept direct scalar calls.
    function book(
        bytes32 from,
        bytes32 to,
        bytes32 liability,
        uint debt,
        bytes32 asset,
        uint amount
    ) internal virtual {
        if (debt != 0) debitAccount(from, liability, debt);
        if (amount != 0) creditAccount(to, asset, amount);
    }

    /// @notice Settle only the debt through BookHook, leaving the position unchanged.
    /// @dev Zero counterparty only debits the active account; an account counterparty
    /// receives the exact payment. Zero debt skips booking and all account hooks.
    function repay(bytes32 account, Position memory position) internal virtual override {
        if (position.debt == 0) return;
        uint amount = position.counterparty == bytes32(0) ? 0 : position.debt;
        book(account, position.counterparty, position.liability, position.debt, position.liability, amount);
    }

    /// @notice Apply the final position quantities exactly; producers enforce limits.
    /// @dev Zero counterparty books on the active account. Account counterparties
    /// exchange the full debt first, then the full asset amount. Producers handle
    /// fees before settlement; this function neither adds nor deducts fees.
    /// Account format is trusted from callers; book and debit/credit hooks need not
    /// repeat boundary validation. Empty exchanges skip those hooks. Malformed
    /// accounts from faulty trusted integrations are not guaranteed to be rejected.
    function settle(bytes32 account, Position memory position) internal virtual override {
        if (position.counterparty == bytes32(0)) {
            book(account, account, position.liability, position.debt, position.asset, position.amount);
            return;
        }
        if (position.debt != 0) {
            book(account, position.counterparty, position.liability, position.debt, position.liability, position.debt);
        }
        if (position.amount != 0) {
            book(position.counterparty, account, position.asset, position.amount, position.asset, position.amount);
        }
    }
}
