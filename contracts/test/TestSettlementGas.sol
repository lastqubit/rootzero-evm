// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

import {Settlement} from "../core/Settlement.sol";
import {Accounts} from "../utils/Accounts.sol";
import {Balances} from "../core/Balances.sol";
import {Limits, Position} from "../core/Types.sol";

/// @dev Benchmark ledger without instrumentation in the account hooks.
contract TestSettlementGas is Settlement, Balances {
    function seed(bytes32 account, bytes32 asset, uint amount) external {
        creditTo(account, asset, amount);
    }

    function balance(bytes32 account, bytes32 asset) external view returns (uint) {
        return balances[account][asset];
    }

    function applyPosition(bytes32 account, Position memory position, Limits memory limits) external {
        settle(account, position, limits);
    }

    function settle(bytes32 account, Position memory position, Limits memory limits) internal override {
        bytes32 counterparty = Accounts.account(position.counterparty);
        uint16 bps = counterparty == hostAccount ? 20 : 2;
        bps = repay(account, counterparty, position.liability, position.debt, bps, limits.debt);
        collect(account, counterparty, position.asset, position.amount, bps, limits.amount);
    }

    function debitAccount(bytes32 account, bytes32 asset, uint amount) internal override {
        debitFrom(account, asset, amount);
    }

    function creditAccount(bytes32 account, bytes32 asset, uint amount) internal override {
        creditTo(account, asset, amount);
    }
}
