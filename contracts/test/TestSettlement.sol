// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

import {Settlement} from "../core/Settlement.sol";
import {Balances} from "../core/Balances.sol";
import {Limits, Position} from "../core/Types.sol";

contract TestSettlement is Settlement, Balances {
    function seed(bytes32 account, bytes32 asset, uint amount) external {
        creditTo(account, asset, amount);
    }

    function balance(bytes32 account, bytes32 asset) external view returns (uint) {
        return balances[account][asset];
    }

    function applyPosition(bytes32 account, Position memory position) external {
        settle(account, position, Limits(0, type(uint).max));
    }

    function applyLimitedPosition(bytes32 account, Position memory position, Limits memory limits) external {
        settle(account, position, limits);
    }

    function debitAccount(bytes32 account, bytes32 asset, uint amount) internal override {
        debitFrom(account, asset, amount);
    }

    function creditAccount(bytes32 account, bytes32 asset, uint amount) internal override {
        creditTo(account, asset, amount);
    }
}
