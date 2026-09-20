// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

import {Accounts} from "../utils/Accounts.sol";
import {SendFailed} from "../utils/Errors.sol";

/// @notice Send an exact chain-asset amount to the address embedded in `account`.
/// @dev Validates the EVM account family and nonzero address, without restricting subtype.
/// Zero amounts still validate the account and call the recipient. Failed transfers revert
/// without copying recipient return data. This helper performs no bookkeeping
/// and emits no events. Callers must authorize and fund the transfer, finalize
/// accounting before calling, and protect their entrypoints against reentrancy.
/// @param account EVM-backed account receiving the chain asset.
/// @param amount Chain-asset amount to send.
function sendChainAsset(bytes32 account, uint amount) {
    address recipient = Accounts.addr(account);
    bool success;
    assembly ("memory-safe") {
        success := call(gas(), recipient, amount, 0, 0, 0, 0)
    }
    if (!success) revert SendFailed();
}

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

/// @notice Hook implemented by hosts that pay chain assets to accounts.
abstract contract CashoutHook {
    /// @notice Pay an exact chain-asset amount to `account`.
    /// Called once per chain-asset BALANCE block in state by the cashout command.
    /// @dev Implementations must revert if the complete amount cannot be paid.
    /// Hosts define account validation, accounting, event emission, and reentrancy protection.
    /// EVM-backed payouts may use sendChainAsset.
    /// @param account Account receiving the chain asset.
    /// @param amount Chain-asset amount to pay.
    function cashout(bytes32 account, uint amount) internal virtual;
}
