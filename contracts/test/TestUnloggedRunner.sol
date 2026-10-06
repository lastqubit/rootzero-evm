// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

import {CommandBase, Execution, Executions, Specs} from "../commands/Base.sol";
import {Runtime} from "../core/Runtime.sol";

/// @dev Identical external transport and callback for each runner candidate.
abstract contract UnloggedRunnerHarness is CommandBase {
    using Executions for Execution;
    uint internal immutable descriptor;
    uint private immutable mode;

    constructor(uint selected, uint mask) Runtime(0) {
        mode = selected;
        descriptor = Executions.describe(
            (selected == 2 ? Specs.Empty : Specs.Balance) | (mask & 1),
            (selected >= 2 ? Specs.AssetAmount : Specs.Empty) | ((mask >> 1) & 1),
            (selected == 0 ? Specs.Empty : Specs.Balance) | ((mask >> 2) & 1)
        );
    }

    function enforceCaller(address caller) internal pure override returns (address) { return caller; }

    function run(bytes calldata context) external payable returns (bytes memory output, uint credit, uint used) {
        uint start = gasleft();
        (output, credit) = execute(context);
        used = start - gasleft();
    }

    function execute(bytes calldata context) internal virtual returns (bytes memory, uint);

    function process(Execution memory exec) internal view {
        bytes32 asset;
        uint amount;
        if (mode != 2) (asset, amount) = exec.unpackBalance();
        if (mode >= 2) {
            (bytes32 other, uint extra) = exec.unpackAssetAmount();
            if (mode == 3) require(asset == other);
            asset = other;
            amount += extra;
        }
        if (mode != 0) exec.outputBalance(asset, amount);
    }

    function shared(bytes calldata context, function(Execution memory) internal callback, bool logging) internal returns (bytes memory output, uint credit) {
        Execution memory exec = openCommand(context, descriptor);
        if (logging) exec.logContext(123, descriptor);
        while (exec.more()) callback(exec);
        output = logging ? exec.finish(123, descriptor) : exec.finish();
        credit = exec.drainBudget();
    }
}

contract RunnerCurrent is UnloggedRunnerHarness {
    constructor(uint mode, uint mask) UnloggedRunnerHarness(mode, mask) {}
    function execute(bytes calldata context) internal override returns (bytes memory, uint) {
        return runCommand(123, descriptor, context, process);
    }
}

contract RunnerSharedLogged is UnloggedRunnerHarness {
    constructor(uint mode, uint mask) UnloggedRunnerHarness(mode, mask) {}
    function execute(bytes calldata context) internal override returns (bytes memory, uint) {
        return shared(context, process, true);
    }
}

contract RunnerSharedUnlogged is UnloggedRunnerHarness {
    constructor(uint mode, uint mask) UnloggedRunnerHarness(mode, mask) {}
    function execute(bytes calldata context) internal override returns (bytes memory, uint) {
        return shared(context, process, false);
    }
}

contract RunnerDirectUnlogged is UnloggedRunnerHarness {
    using Executions for Execution;
    constructor(uint mode, uint mask) UnloggedRunnerHarness(mode, mask) {}
    function execute(bytes calldata context) internal override returns (bytes memory output, uint credit) {
        Execution memory exec = openCommand(context, descriptor);
        while (exec.more()) process(exec);
        output = exec.finish();
        credit = exec.drainBudget();
    }
}

/// @dev Both entrypoints coexist, as in a host with logged and unlogged commands.
contract RunnerMixedCurrent is RunnerCurrent {
    constructor(uint mode, uint mask) RunnerCurrent(mode, mask) {}
    function logged(bytes calldata context) external payable returns (bytes memory, uint) {
        return runCommand(123, descriptor, context, process);
    }
}

contract RunnerMixedShared is RunnerSharedUnlogged {
    constructor(uint mode, uint mask) RunnerSharedUnlogged(mode, mask) {}
    function logged(bytes calldata context) external payable returns (bytes memory, uint) {
        return shared(context, process, true);
    }
}

contract RunnerMixedDirect is RunnerDirectUnlogged {
    constructor(uint mode, uint mask) RunnerDirectUnlogged(mode, mask) {}
    function logged(bytes calldata context) external payable returns (bytes memory, uint) {
        return runCommand(123, descriptor, context, process);
    }
}
