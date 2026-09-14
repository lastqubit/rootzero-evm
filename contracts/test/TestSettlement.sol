// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

import {Settlement} from "../core/Settlement.sol";
import {Balances} from "../core/Balances.sol";
import {Position} from "../core/Types.sol";
import {Positions} from "../utils/Positions.sol";
import {Accounts} from "../utils/Accounts.sol";

contract TestSettlement is Settlement, Balances {
    event AccountOperation(bool debit, bytes32 account, bytes32 asset, uint amount);
    event Applied(bytes32 from, bytes32 to, bytes32 asset, uint amount, bytes32 liability, uint debt);

    function book(bytes32 from, bytes32 to, bytes32 asset, uint amount, bytes32 liability, uint debt)
        internal override
    {
        emit Applied(from, to, asset, amount, liability, debt);
        Settlement.book(from, to, asset, amount, liability, debt);
    }

    function seed(bytes32 account, bytes32 asset, uint amount) external {
        creditTo(account, asset, amount);
    }

    function balance(bytes32 account, bytes32 asset) external view returns (uint) {
        return balances[account][asset];
    }

    function applyPosition(bytes32 account, Position memory position) external {
        Positions.requireLimits(position, type(uint128).max);
        settle(account, position);
    }

    function applyLimitedPosition(bytes32 account, Position memory position, uint limits) external {
        Positions.requireLimits(position, limits);
        settle(account, position);
    }


    function debitAccount(bytes32 account, bytes32 asset, uint amount) internal virtual override {
        debitFrom(account, asset, amount);
        emit AccountOperation(true, account, asset, amount);
    }

    function creditAccount(bytes32 account, bytes32 asset, uint amount) internal virtual override {
        creditTo(account, asset, amount);
        emit AccountOperation(false, account, asset, amount);
    }
}

/// @dev A host that chooses the standard account format in its account hooks.
contract TestValidatedSettlement is TestSettlement {
    function debitAccount(bytes32 account, bytes32 asset, uint amount) internal override {
        super.debitAccount(Accounts.account(account), asset, amount);
    }

    function creditAccount(bytes32 account, bytes32 asset, uint amount) internal override {
        super.creditAccount(Accounts.account(account), asset, amount);
    }
}
