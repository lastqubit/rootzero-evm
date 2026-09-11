// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

import {Realize} from "../commands/Realize.sol";
import {ExecuteSettle} from "../commands/Settle.sol";
import {ExecuteBook} from "../commands/Book.sol";
import {Settlement, SettleHook, BookHook} from "../core/Settlement.sol";
import {Balances} from "../core/Balances.sol";
import {Pipeline} from "../core/Pipeline.sol";
import {Runtime} from "../core/Runtime.sol";
import {Limits, Position} from "../core/Types.sol";
import {AccessDenied} from "../core/Access.sol";
import {UnexpectedValue} from "../utils/Errors.sol";
import {Accounts} from "../utils/Accounts.sol";
import {Nodes} from "../utils/Nodes.sol";

/// @dev Test-only host backing positions with a reserve ledger. Realization
/// commits reserves and records the receivable; booking collects it.
contract TestCounterpartyPipeline is Realize, ExecuteSettle, ExecuteBook, Settlement, Balances, Pipeline {
    address private immutable tester = msg.sender;
    bool private immutable memorySettlement;
    uint public realizations;
    uint public memorySettlements;

    constructor(bool useMemory) Runtime(0) {
        memorySettlement = useMemory;
    }

    function seedHost(bytes32 asset, uint amount) external { creditTo(Accounts.toHost(host), asset, amount); }
    function seedAccount(bytes32 account, bytes32 asset, uint amount) external { creditTo(account, asset, amount); }
    function hostBalance(bytes32 asset) external view returns (uint) { return balances[Accounts.toHost(host)][asset]; }
    function accountBalance(bytes32 account, bytes32 asset) external view returns (uint) {
        return balances[account][asset];
    }

    function run(bytes32 account, bytes memory state, bytes calldata steps) external returns (uint) {
        enforceCaller(msg.sender);
        return pipe(account, state, steps, 0);
    }

    function enforceCaller(address caller) internal view override returns (address) {
        if (caller != tester && caller != address(this)) revert AccessDenied();
        return caller;
    }

    function enforceCommand(uint cmd) internal view override returns (bytes4, address) {
        if (cmd != bookId() && cmd != settleId() && cmd != Nodes.toCommand("realize", address(this))) revert AccessDenied();
        return Nodes.decode(cmd);
    }

    function execute(uint cmd, bytes32 account, bytes memory state, bytes calldata input, uint value)
        internal override returns (bool, bytes memory, uint)
    {
        if (memorySettlement && cmd == settleId()) {
            enforceCommand(cmd);
            ++memorySettlements;
            return executeSettle(account, state, input, value);
        }
        if (memorySettlement && cmd == bookId()) {
            enforceCommand(cmd);
            ++memorySettlements;
            return executeBook(account, state, input, value);
        }
        return (false, state, 0);
    }

    function realize(bytes32 account, Position memory position) internal override returns (Position memory) {
        if (position.counterparty != Accounts.toHost(host)) revert UnexpectedValue();
        ++realizations;
        if (position.amount != 0) debitFrom(Accounts.toHost(host), position.asset, position.amount);
        if (position.debt != 0) creditTo(Accounts.toHost(host), position.liability, position.debt);
        // Return a fresh struct to exercise propagation of the hook's result.
        Position memory result = Position(position.asset, position.amount, position.liability, position.debt, bytes32(0));
        return result;
    }

    function settle(bytes32 account, Position memory position, Limits memory limits) internal override(SettleHook) {
        bytes32 counterparty = Accounts.account(position.counterparty);
        uint16 bps = counterparty == hostAccount ? 20 : 2;
        bps = repay(account, counterparty, position.liability, position.debt, bps, limits.debt);
        collect(account, counterparty, position.asset, position.amount, bps, limits.amount);
    }

    function book(bytes32 from, bytes32 to, bytes32 asset, uint amount, bytes32 liability, uint debt)
        internal override(Settlement, BookHook)
    {
        Settlement.book(from, to, asset, amount, liability, debt);
    }

    function debitAccount(bytes32 account, bytes32 asset, uint amount) internal override {
        debitFrom(account, asset, amount);
    }

    function creditAccount(bytes32 account, bytes32 asset, uint amount) internal override {
        creditTo(account, asset, amount);
    }
}
