// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

import {EventEmitter} from "./Emitter.sol";

/// @notice Emitted when an account balance changes.
/// @dev Reports the resulting balance. Indexers derive deltas from ordered updates.
abstract contract BalanceEvent is EventEmitter {
    string private constant ABI = "event Balance(bytes32 indexed account, bytes32 asset, uint balance)";

    /// @param account Account identifier whose balance changed.
    /// @param asset Asset identifier.
    /// @param balance New balance after the change.
    event Balance(bytes32 indexed account, bytes32 asset, uint balance);

    constructor() {
        emit EventAbi(ABI);
    }
}
