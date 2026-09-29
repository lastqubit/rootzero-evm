// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

import {ActivityEvent} from "../events/Activity.sol";

// Identical inputs; compare the previous packed event with the generic event.
// The previous ABI has no subject field. Measurements exclude call decoding.
contract PreviousActivityEventGas {
    event Activity(bytes32 indexed account, uint codes, uint id);

    function measure(bytes32 account, bytes32 subject, uint codes, uint value) external returns (uint used) {
        uint initial = gasleft();
        emit Activity(account, codes, value);
        used = initial - gasleft();
    }
}

contract TestActivityEventGas is ActivityEvent {
    function measure(bytes32 account, bytes32 subject, uint codes, uint value) external returns (uint used) {
        uint initial = gasleft();
        emit Activity(account, subject, value, codes);
        used = initial - gasleft();
    }
}
