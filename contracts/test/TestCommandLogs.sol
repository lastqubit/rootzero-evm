// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

import {CommandBase, Execution, Executions, Specs} from "../commands/Base.sol";

import {Lanes} from "../codec/Lanes.sol";
import {Runtime} from "../core/Runtime.sol";

contract TestCommandLogs is CommandBase {
    using Executions for Execution;

    uint public immutable id;
    uint public immutable descriptor;
    bytes private nested;
    event Processed(uint amount);
    error Rejected();

    constructor(uint stateCodes, uint inputCodes, uint outputCodes, uint8 flags) Runtime(0) {
        (id, descriptor) = command("run", Lanes.create(Specs.Balance, stateCodes), Lanes.create(Specs.AssetAmount, inputCodes), Lanes.create(Specs.Balance, outputCodes), flags);
    }

    function enforceCaller(address caller) internal pure override returns (address) { return caller; }

    function setNested(bytes calldata context) external { nested = context; }

    function run(bytes calldata context) external payable returns (bytes memory, uint) {
        return runCommand(id, descriptor, context, process);
    }

    function process(Execution memory exec) private {
        (bytes32 asset, uint amount) = exec.unpackBalance();
        (bytes32 other, uint increment) = exec.unpackAssetAmount();
        if (asset != other || increment == 13) revert Rejected();
        if (nested.length != 0) {
            bytes memory context = nested;
            delete nested;
            this.run(context);
        }
        emit Processed(amount);
        exec.outputBalance(asset, amount + increment);
    }
}
