// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

import {BalanceEvent} from "../events/Balance.sol";

// Identical call signatures keep calldata costs out of the comparison. Measure
// the emission inside each call, excluding dispatch, decoding and return encoding.
contract PreviousBalanceEventGas {
    event Balance(bytes32 indexed account, bytes32 asset, uint balance, int change);

    function measure(bytes32 account, bytes32 asset, uint balance, int change) external returns (uint used) {
        uint initial = gasleft();
        emit Balance(account, asset, balance, change);
        used = initial - gasleft();
    }
}

contract TestBalanceEventGas is BalanceEvent {
    function measure(bytes32 account, bytes32 asset, uint balance, int) external returns (uint used) {
        uint initial = gasleft();
        emit Balance(account, asset, balance);
        used = initial - gasleft();
    }
}
