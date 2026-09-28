// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

import {ActivityEvent} from "../events/Activity.sol";

// Identical inputs; measure emission and any packing, excluding call decoding.
contract PreviousActivityEventGas {
    event Activity(bytes32 indexed account, uint actions, uint effects, uint id);

    function measure(bytes32 account, uint32 action, uint32 effect, uint id) external returns (uint used) {
        uint initial = gasleft();
        emit Activity(account, action, effect, id);
        used = initial - gasleft();
    }
}

contract TestActivityEventGas is ActivityEvent {
    function measure(bytes32 account, uint32 action, uint32 effect, uint id) external returns (uint used) {
        uint initial = gasleft();
        uint codes = action == 0 ? uint(effect) : uint(action) | (uint(effect) << 32);
        emit Activity(account, codes, id);
        used = initial - gasleft();
    }
}
