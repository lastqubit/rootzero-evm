// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

import {EventEmitter} from "./Emitter.sol";

/// @notice Emitted when an action produces an account position.
abstract contract PositionedEvent is EventEmitter {
    string private constant ABI =
        "event Positioned(bytes32 indexed account, bytes32 asset, uint amount, bytes32 liability, uint debt, bytes32 counterparty, uint32 action)";

    /// @param account Account associated with the position.
    /// @param asset Identifier for the asset side.
    /// @param amount Quantity on the asset side.
    /// @param liability Identifier for the liability side.
    /// @param debt Quantity owed on the liability side.
    /// @param counterparty Counterparty identifier from the resulting position.
    /// @param action Primary operation hint from `Actions` that produced the position.
    event Positioned(
        bytes32 indexed account,
        bytes32 asset,
        uint amount,
        bytes32 liability,
        uint debt,
        bytes32 counterparty,
        uint32 action
    );

    constructor() {
        emit EventAbi(ABI);
    }
}

/// @notice Emitted after an account position has been fully settled.
abstract contract SettledEvent is EventEmitter {
    string private constant ABI =
        "event Settled(bytes32 indexed account, bytes32 asset, uint amount, bytes32 liability, uint debt, bytes32 counterparty)";

    /// @param account Account whose position was settled.
    /// @param asset Identifier for the asset side.
    /// @param amount Settled asset quantity.
    /// @param liability Identifier for the liability side.
    /// @param debt Settled debt quantity, excluding additional fees.
    /// @param counterparty Counterparty identifier from the settled position.
    event Settled(
        bytes32 indexed account,
        bytes32 asset,
        uint amount,
        bytes32 liability,
        uint debt,
        bytes32 counterparty
    );

    constructor() {
        emit EventAbi(ABI);
    }
}
