// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

import {ReceivedEvent} from "../events/Received.sol";
import {SpentEvent} from "../events/Spent.sol";
import {LockedEvent} from "../events/Locked.sol";
import {UnlockedEvent} from "../events/Unlocked.sol";
import {NodeEvent} from "../events/Node.sol";
import {GuardianEvent} from "../events/Guardian.sol";

contract TestEventCodes is ReceivedEvent, SpentEvent, LockedEvent, UnlockedEvent, NodeEvent, GuardianEvent {
    function emitReceived(bytes32 account, bytes32 asset, uint amount, uint codes) external {
        emit Received(account, asset, amount, codes);
    }
    function emitSpent(bytes32 account, bytes32 asset, uint amount, uint codes) external {
        emit Spent(account, asset, amount, codes);
    }
    function emitLocked(bytes32 account, bytes32 asset, uint amount, uint codes) external {
        emit Locked(account, asset, amount, codes);
    }
    function emitUnlocked(bytes32 account, bytes32 asset, uint amount, uint codes) external {
        emit Unlocked(account, asset, amount, codes);
    }
    function emitNode(uint host, uint node, uint codes) external {
        emit Node(host, node, codes);
    }
    function emitGuardian(uint host, bytes32 account, uint codes) external {
        emit Guardian(host, account, codes);
    }
}
