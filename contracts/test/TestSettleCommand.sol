// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

import {ExecuteSettle} from "../commands/Settle.sol";
import {Settlement, SettleHook} from "../core/Settlement.sol";
import {Balances} from "../core/Balances.sol";
import {Pipeline} from "../core/Pipeline.sol";
import {Runtime} from "../core/Runtime.sol";
import {Position} from "../core/Types.sol";
import {Nodes} from "../utils/Nodes.sol";
import {AccessDenied} from "../core/Access.sol";

contract TestSettleCommand is ExecuteSettle, Settlement, Balances, Pipeline {
    address private immutable tester = msg.sender;
    event BookCalled(bytes32 account);
    event DebitCalled(bytes32 asset, uint amount);
    event CreditCalled(bytes32 asset, uint amount);

    constructor() Runtime(0) {}

    function seed(bytes32 account, bytes32 asset, uint amount) external { creditTo(account, asset, amount); }
    function balance(bytes32 account, bytes32 asset) external view returns (uint) { return balances[account][asset]; }
    function commandId() external view returns (uint) { return settleId(); }

    function run(bytes32 account, bytes memory state, bytes calldata steps) external payable returns (uint) {
        enforceCaller(msg.sender);
        return pipe(account, state, steps, msg.value);
    }

    function enforceCaller(address caller) internal view override returns (address) {
        if (caller != tester && caller != address(this)) revert AccessDenied();
        return caller;
    }

    function enforceCommand(uint cmd) internal view override returns (bytes4, address) {
        if (cmd != settleId()) revert AccessDenied();
        return Nodes.decode(cmd);
    }

    function execute(uint cmd, bytes32 account, bytes memory state, bytes calldata input, uint value)
        internal override returns (bool, bytes memory, uint)
    {
        enforceCommand(cmd);
        return executeSettle(account, state, input, value);
    }

    function book(bytes32 from, bytes32 to, bytes32 asset, uint amount, bytes32 liability, uint debt)
        internal override
    {
        emit BookCalled(from);
        Settlement.book(from, to, asset, amount, liability, debt);
    }

    function settle(bytes32 account, Position memory position)
        internal override(Settlement, SettleHook)
    {
        Settlement.settle(account, position);
    }

    function debitAccount(bytes32 account, bytes32 asset, uint amount) internal override {
        emit DebitCalled(asset, amount);
        debitFrom(account, asset, amount);
    }

    function creditAccount(bytes32 account, bytes32 asset, uint amount) internal override {
        emit CreditCalled(asset, amount);
        creditTo(account, asset, amount);
    }

}
