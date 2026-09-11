// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

import {PositionedEvent} from "../events/Position.sol";

contract TestPositionedEvent is PositionedEvent {
    function emitPositioned(
        bytes32 account,
        bytes32 asset,
        uint amount,
        bytes32 liability,
        uint debt,
        bytes32 counterparty,
        uint32 action
    ) external {
        emit Positioned(account, asset, amount, liability, debt, counterparty, action);
    }
}
