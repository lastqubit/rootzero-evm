// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

import {CommandHost} from "../Core.sol";
import {Nodes} from "../Utils.sol";
import {CommandBase, Execution, Executions, Specs} from "../commands/Base.sol";

/// @notice Unrestricted synthetic endpoints for measuring the shared batch runner.
contract CommandRunnerBenchmark is CommandHost, CommandBase {
    using Executions for Execution;
    uint private immutable sinkDescriptor;
    uint private immutable stateDescriptor;
    uint private immutable inputDescriptor;
    uint private immutable pairedDescriptor;

    constructor() CommandHost(Nodes.toHost(msg.sender)) {
        (, sinkDescriptor) = command("sinkBatch", Specs.Balance, Specs.Empty, Specs.Empty, 0);
        (, stateDescriptor) = command("stateBatch", Specs.Balance, Specs.Empty, Specs.Balance, 0);
        (, inputDescriptor) = command("inputBatch", Specs.Empty, Specs.Amount, Specs.Balance, 0);
        (, pairedDescriptor) = command("pairedBatch", Specs.Balance, Specs.Amount, Specs.Balance, 0);
    }

    function batch(bytes calldata context, uint mode) external payable returns (bytes memory, uint) {
        if (mode == 0) return runCommand(context, sinkDescriptor, sink);
        if (mode == 1) return runCommand(context, stateDescriptor, copyState);
        if (mode == 2) return runCommand(context, inputDescriptor, copyInput);
        require(mode == 3);
        return runCommand(context, pairedDescriptor, pair);
    }

    function single(bytes calldata context) external payable returns (bytes memory, uint) {
        return runCommandOnce(context, stateDescriptor, copyState);
    }

    function sink(Execution memory exec) private pure { exec.unpackBalance(); }

    function copyState(Execution memory exec) private pure {
        (bytes32 asset, uint amount) = exec.unpackBalance();
        exec.outputBalance(asset, amount);
    }

    function copyInput(Execution memory exec) private pure {
        (bytes32 asset, uint amount) = exec.unpackAmount();
        exec.outputBalance(asset, amount);
    }

    function pair(Execution memory exec) private pure {
        (bytes32 asset, uint amount) = exec.unpackBalance();
        (bytes32 other, uint increment) = exec.unpackAmount();
        require(asset == other);
        exec.outputBalance(asset, amount + increment);
    }
}
