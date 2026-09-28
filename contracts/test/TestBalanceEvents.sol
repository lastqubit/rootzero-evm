// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

import {BalanceEvent} from "../Events.sol";

contract TestBalanceEvents is BalanceEvent {
    function emitBalance(bytes32 account, bytes32 asset, uint balance) external {
        emit Balance(account, asset, balance);
    }

}
