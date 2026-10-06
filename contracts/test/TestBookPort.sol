// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

import {Booking} from "../core/Types.sol";

import {BookPort} from "../ports/Book.sol";
import {Balances} from "../core/Balances.sol";
import {Runtime} from "../core/Runtime.sol";
import {AccessDenied} from "../core/Access.sol";

contract TestBookPort is BookPort, Balances {
    address private immutable peer;
    event Debited(bytes32 account, bytes32 asset, uint amount);
    event Credited(bytes32 account, bytes32 asset, uint amount);

    constructor(address trustedPeer) Runtime(0) { peer = trustedPeer; }

    function seed(bytes32 account, bytes32 asset, uint amount) external { creditTo(account, asset, amount); }
    function balance(bytes32 account, bytes32 asset) external view returns (uint) { return balances[account][asset]; }

    function enforcePeer(address caller) internal view override returns (address) {
        if (caller != peer) revert AccessDenied();
        return caller;
    }

    function book(Booking memory value) internal override {
        if (value.debt != 0) debitAccount(value.from, value.liability, value.debt);
        if (value.amount != 0) creditAccount(value.to, value.asset, value.amount);
    }

    function debitAccount(bytes32 account, bytes32 asset, uint amount) internal {
        debitFrom(account, asset, amount);
        emit Debited(account, asset, amount);
    }

    function creditAccount(bytes32 account, bytes32 asset, uint amount) internal {
        creditTo(account, asset, amount);
        emit Credited(account, asset, amount);
    }
}
