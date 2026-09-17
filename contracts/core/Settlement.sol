// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

import {Position} from "./Types.sol";
import {HostAccount} from "./Runtime.sol";

/// @title DebitAccountHook
/// @notice Hook for exactly debiting externally managed account funds.
abstract contract DebitAccountHook {
    /// @notice Override to debit exactly `amount` from externally managed `account` funds.
    /// @dev Returning successfully asserts that the complete amount was debited. The
    /// hook must revert if it cannot debit the exact amount. Internal bookkeeping fees
    /// must not reduce the amount made available to the consuming operation.
    /// Implementations validate and authorize the source account.
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
    /// Implementations validate the destination account under host policy.
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
    /// enforce limits and fees. Implementations validate accounts, directly or
    /// through the debit/credit hooks. Preserve debit-first
    /// funding requirements even when accounts or assets match; do not net the legs.
    /// @param from Account debited for the liability.
    /// @param to Account credited with the asset.
    /// @param asset Asset identifier for the credit.
    /// @param amount Exact quantity to credit.
    /// @param liability Asset identifier for the debit.
    /// @param debt Exact quantity to debit.
    function book(bytes32 from, bytes32 to, bytes32 asset, uint amount, bytes32 liability, uint debt) internal virtual;
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
    /// @param position Full position; the hook validates the counterparty and authorizes the repayment.
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
    /// @param position Full position; the hook validates the counterparty and authorizes the exchange.
    function settle(bytes32 account, Position memory position) internal virtual;
}

/// @title Settlement
/// @notice Default application of debit/credit legs plus reusable settlement mechanics.
/// @dev Intended for hosts that maintain account balances. Hosts without their own
/// balance ledger implement RealizeHook instead; a production host chooses one
/// position-fulfillment model. Producers supply final quantities with fees already handled.
/// Trusted position producers and account hooks remain responsible for authorization.
abstract contract Settlement is HostAccount, DebitAccountHook, CreditAccountHook, BookHook, RepayHook, SettleHook {
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

    /// @notice Settle only the debt through BookHook, leaving the position unchanged.
    /// @dev Zero counterparty only debits the active account; an account counterparty
    /// receives the exact payment. Zero debt skips booking and account validation.
    function repay(bytes32 account, Position memory position) internal virtual override {
        if (position.debt == 0) return;
        uint amount = position.counterparty == bytes32(0) ? 0 : position.debt;
        book(account, position.counterparty, position.liability, amount, position.liability, position.debt);
    }

    /// @notice Apply the final position quantities exactly; producers enforce limits.
    /// @dev Zero counterparty books on the active account. Account counterparties
    /// exchange the full debt first, then the full asset amount. Producers handle
    /// fees before settlement; this function neither adds nor deducts fees.
    /// Account validation belongs to book and its debit/credit hooks. Empty
    /// exchanges skip those hooks and therefore do not validate the counterparty.
    function settle(bytes32 account, Position memory position) internal virtual override {
        if (position.counterparty == bytes32(0)) {
            book(account, account, position.asset, position.amount, position.liability, position.debt);
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
