// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

import {CashoutHook, sendChainAsset} from "../core/Cash.sol";

contract TestCashoutHook is CashoutHook {
    uint public paid;
    receive() external payable {}

    function pay(bytes32 account, uint amount) external {
        paid += amount;
        cashout(account, amount);
    }

    function cashout(bytes32 account, uint amount) internal override {
        sendChainAsset(account, amount);
    }
}

contract TestCashoutRecipient {
    uint public received;
    uint public calls;
    uint public paidDuringCallback;
    uint private immutable response;

    constructor(uint mode) { response = mode; }

    receive() external payable {
        if (response == 1) {
            assembly ("memory-safe") { revert(mload(0x40), 0x10000) }
        }
        received += msg.value;
        calls++;
        paidDuringCallback = TestCashoutHook(payable(msg.sender)).paid();
        if (response == 2) {
            assembly ("memory-safe") { return(mload(0x40), 0x10000) }
        }
    }
}
