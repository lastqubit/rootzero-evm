// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

import {CommandBase, Execution, Executions, Specs} from "../commands/Base.sol";
import {PortBase} from "../ports/Base.sol";
import {Runtime} from "../core/Runtime.sol";

contract TestExecutionCallbacks is CommandBase, PortBase {
    using Executions for Execution;

    error RejectedRequest();

    uint public processed;
    bytes32 public lastAccount;
    address public lastCaller;

    constructor() Runtime(0) {}

    function enforceCaller(address caller) internal pure override returns (address) {
        return caller;
    }

    function enforcePeer(address peer) internal pure override returns (address) {
        return peer;
    }

    // Test entrypoint deliberately bypasses access control.
    function execute(bytes calldata context) external payable returns (bytes memory, uint) {
        return runCommand(context, Executions.describe(0, Specs.Amount, Specs.Amount, 0), processOne);
    }

    function executeState(bytes calldata context) external payable returns (bytes memory, uint) {
        return runCommand(context, Executions.describe(Specs.Balance, 0, Specs.Amount, 0), processState);
    }

    function executeOnce(bytes calldata context) external payable returns (bytes memory, uint) {
        return runCommandOnce(context, Executions.describe(0, Specs.Amount, Specs.Amount, 0), processOne);
    }

    function executeOnceEmpty(bytes calldata context) external payable returns (bytes memory, uint) {
        return runCommandOnce(context, Executions.describe(0, 0, 0, 0), processEmpty);
    }

    function executePort(bytes calldata input) external payable returns (bytes memory, uint) {
        return runPort(input, Executions.describe(0, Specs.Amount, Specs.Amount, 0), processPort);
    }

    function processPort(Execution memory exec) private {
        exec.useValue(1);
        processOne(exec);
    }

    function processEmpty(Execution memory exec) private {
        processed++;
        lastAccount = exec.account;
        exec.useValue(1);
    }

    function executeManual(bytes calldata context) external payable returns (bytes memory, uint) {
        Execution memory exec = openCommand(context, Executions.describe(0, Specs.Amount, Specs.Amount, 0));
        while (exec.more()) processOne(exec);
        return exec.close();
    }

    function processState(Execution memory exec) internal pure {
        (bytes32 asset, uint amount) = exec.unpackBalance();
        exec.useValue(1);
        exec.outputAmount(asset, amount);
    }

    function processOne(Execution memory exec) internal {
        (bytes32 asset, uint amount) = exec.unpackAmount();
        if (amount == 13) revert RejectedRequest();
        processed++;
        lastAccount = exec.account;
        lastCaller = msg.sender;
        exec.outputAmount(asset, amount * 2);
    }
}
