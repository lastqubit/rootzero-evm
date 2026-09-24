// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

import {Settlement} from "../core/Settlement.sol";
import {Balances} from "../core/Balances.sol";
import {Position} from "../core/Types.sol";
import {OutOfRange} from "../utils/Errors.sol";

/// @dev Benchmark ledger without instrumentation in the account hooks.
contract TestSettlementGas is Settlement, Balances {
    function seed(bytes32 account, bytes32 asset, uint amount) external {
        creditTo(account, asset, amount);
    }

    function balance(bytes32 account, bytes32 asset) external view returns (uint) {
        return balances[account][asset];
    }

    function applyPosition(bytes32 account, Position memory position, uint limits) external {
        if (position.amount < limits >> 128 || position.debt > uint128(limits)) revert OutOfRange();
        settle(account, position);
    }


    function debitAccount(bytes32 account, bytes32 asset, uint amount) internal override {
        debitFrom(account, asset, amount);
    }

    function creditAccount(bytes32 account, bytes32 asset, uint amount) internal override {
        creditTo(account, asset, amount);
    }
}
