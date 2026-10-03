// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

import {CommandHost} from "../Core.sol";
import {Nodes} from "../Utils.sol";
import {CommandBase, Execution, Executions, Specs} from "../commands/Base.sol";

/// @notice Unrestricted synthetic endpoints for measuring the shared batch runner.
contract CommandRunnerBenchmark is CommandHost, CommandBase {
    using Executions for Execution;
    uint private immutable sinkDescriptor;
    uint private immutable sinkId;
    uint private immutable stateDescriptor;
    uint private immutable stateId;
    uint private immutable inputDescriptor;
    uint private immutable inputId;
    uint private immutable pairedDescriptor;
    uint private immutable pairedId;

    constructor() CommandHost(Nodes.toHost(msg.sender)) {
        (sinkId, sinkDescriptor) = command("sinkBatch", Specs.Balance, Specs.Empty, Specs.Empty, 0);
        (stateId, stateDescriptor) = command("stateBatch", Specs.Balance, Specs.Empty, Specs.Balance, 0);
        (inputId, inputDescriptor) = command("inputBatch", Specs.Empty, Specs.AssetAmount, Specs.Balance, 0);
        (pairedId, pairedDescriptor) = command("pairedBatch", Specs.Balance, Specs.AssetAmount, Specs.Balance, 0);
    }

    function batch(bytes calldata context, uint mode) external payable returns (bytes memory, uint) {
        if (mode == 0) return runCommand(sinkId, sinkDescriptor, context, sink);
        if (mode == 1) return runCommand(stateId, stateDescriptor, context, copyState);
        if (mode == 2) return runCommand(inputId, inputDescriptor, context, copyInput);
        require(mode == 3);
        return runCommand(pairedId, pairedDescriptor, context, pair);
    }

    function single(bytes calldata context) external payable returns (bytes memory, uint) {
        return runCommandOnce(stateId, stateDescriptor, context, copyState);
    }

    function sink(Execution memory exec) private pure { exec.unpackBalance(); }

    function copyState(Execution memory exec) private pure {
        (bytes32 asset, uint amount) = exec.unpackBalance();
        exec.outputBalance(asset, amount);
    }

    function copyInput(Execution memory exec) private pure {
        (bytes32 asset, uint amount) = exec.unpackAssetAmount();
        exec.outputBalance(asset, amount);
    }

    function pair(Execution memory exec) private pure {
        (bytes32 asset, uint amount) = exec.unpackBalance();
        (bytes32 other, uint increment) = exec.unpackAssetAmount();
        require(asset == other);
        exec.outputBalance(asset, amount + increment);
    }
}
