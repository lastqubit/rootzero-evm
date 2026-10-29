// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

import {SendFailed} from "../utils/Errors.sol";
import {ensureAddr} from "../utils/Utils.sol";

/// @notice Send an exact chain-asset amount to `recipient`.
/// @dev Reverts with `ZeroAddress` for a zero recipient. Zero amounts still call the recipient.
/// Failed transfers revert without copying recipient return data. This helper performs no
/// bookkeeping and emits no events. Callers must authorize and fund the transfer, finalize
/// accounting before calling, and protect their entrypoints against reentrancy.
/// @param recipient Address receiving the chain asset.
/// @param amount Chain-asset amount to send.
function sendChainAsset(address recipient, uint amount) {
    ensureAddr(recipient);
    bool success;
    assembly ("memory-safe") {
        success := call(gas(), recipient, amount, 0, 0, 0, 0)
    }
    if (!success) revert SendFailed();
}

/// @title CashinHook
/// @notice Hook implemented by hosts that credit native value to accounts.
abstract contract CashinHook {
    /// @notice Credit an exact chain-asset amount already held by the host to `account`.
    /// @dev Returning successfully asserts that the complete amount was credited.
    /// Implementations must revert when the requested amount cannot be credited.
    /// May assume supplied accounts satisfy the caller's account policy without
    /// repeated format checks. Implementations define zero-account handling where
    /// applicable; portPipePayable skips cashin for a zero final account.
    /// Operation requirements still apply.
    /// Callers must consume the amount from their budget so it cannot be reused.
    /// @param account Account whose chain asset is credited.
    /// @param amount Native-asset amount to credit.
    function cashin(bytes32 account, uint amount) internal virtual;
}

/// @title CashoutHook
/// @notice Hook implemented by hosts that pay chain assets to addresses.
abstract contract CashoutHook {
    /// @notice Pay an exact chain-asset amount to `recipient`.
    /// @dev Called once per chain-asset PAYOUT block in state by the cashout command, with
    /// its recipient decoded as a nonzero EVM address.
    /// Implementations must revert if the complete amount cannot be paid.
    /// Hosts still enforce payout destination requirements, accounting, event emission,
    /// and reentrancy protection. Implementations may use sendChainAsset.
    /// @param recipient Address receiving the chain asset.
    /// @param amount Chain-asset amount to pay.
    function cashout(address recipient, uint amount) internal virtual;
}
