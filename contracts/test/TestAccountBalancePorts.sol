// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

import {Balances} from "../core/Balances.sol";
import {CreditAccountPort} from "../ports/Credit.sol";
import {DebitAccountPort} from "../ports/Debit.sol";
import {GetBalance} from "../queries/Balance.sol";
import {Runtime} from "../core/Runtime.sol";
import {AccessDenied} from "../core/Access.sol";

contract TestAccountBalancePorts is Balances, CreditAccountPort, DebitAccountPort, GetBalance {
    address private immutable peer = msg.sender;
    constructor() Runtime(0) {}

    function enforcePeer(address caller) internal view override returns (address) {
        if (caller != peer) revert AccessDenied();
        return caller;
    }

    function creditAccount(bytes32 account, bytes32 asset, uint amount) internal override {
        creditTo(account, asset, amount);
    }

    function debitAccount(bytes32 account, bytes32 asset, uint amount) internal override {
        debitFrom(account, asset, amount);
    }

    function getBalance(bytes32 account, bytes32 asset) internal view override returns (uint) {
        return balances[account][asset];
    }
}
