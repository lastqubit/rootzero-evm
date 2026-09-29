// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

import {ActivityEvent} from "../events/Activity.sol";
import {NodeEvent} from "../events/Node.sol";
import {GuardianEvent} from "../events/Guardian.sol";

contract TestEventCodes is ActivityEvent, NodeEvent, GuardianEvent {
    function emitActivity(bytes32 account, bytes32 subject, uint value, uint codes) external {
        emit Activity(account, subject, value, codes);
    }
    function emitNode(uint host, uint node, uint codes) external {
        emit Node(host, node, codes);
    }
    function emitGuardian(uint host, bytes32 account, uint codes) external {
        emit Guardian(host, account, codes);
    }
}
