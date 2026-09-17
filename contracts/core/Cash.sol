// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

import {Accounts} from "../utils/Accounts.sol";
import {Actions} from "../utils/Actions.sol";
import {ChainAsset} from "./Runtime.sol";
import {SpentEvent} from "../events/Spent.sol";

/// @notice Hook implemented by hosts that credit native value to accounts.
abstract contract CashinHook {
    /// @notice Credit an exact chain-asset amount already held by the host to `account`.
    /// @dev Returning successfully asserts that the complete amount was credited.
    /// Implementations must revert when the requested amount cannot be credited.
    /// Implementations are responsible for account validation, including zero-account policy.
    /// Callers must consume the amount from their budget so it cannot be reused.
    /// @param account Account whose chain asset is credited.
    /// @param amount Native-asset amount to credit.
    function cashin(bytes32 account, uint amount) internal virtual;
}

/// @notice Overridable native payout for EVM-backed accounts.
abstract contract CashoutHook is ChainAsset, SpentEvent {
    error CashoutFailed();

    /// @notice Pay an exact chain-asset amount to the address embedded in `account`.
    /// Called once per chain-asset BALANCE block in state by the cashout command.
    /// @dev Validates the EVM account family and nonzero address, without restricting subtype.
    /// Callers must authorize and fund the withdrawal and finalize accounting before this call.
    /// Zero amounts return without validation, transfer, or event emission.
    /// This hook does not debit a ledger. The recipient may execute code;
    /// the host is responsible for protecting its entrypoints against reentrancy.
    /// Failed transfers revert without copying recipient return data. Successful transfers emit Spent.
    /// @param account EVM-backed account receiving the native asset.
    /// @param amount Native-asset amount to pay.
    function cashout(bytes32 account, uint amount) internal virtual {
        if (amount == 0) return;
        address recipient = Accounts.addr(account);
        bool success;
        assembly ("memory-safe") {
            success := call(gas(), recipient, amount, 0, 0, 0, 0)
        }
        if (!success) revert CashoutFailed();
        emit Spent(account, chainAsset, amount, Actions.Cashout, 0);
    }
}
