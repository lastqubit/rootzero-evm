// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

import {CommandBase, Execution, Executions, Specs} from "../commands/Base.sol";

import {Runtime} from "../core/Runtime.sol";
import {Encoder} from "../codec/Encoder.sol";

contract TestCommandLogs is CommandBase {
    using Executions for Execution;

    uint public immutable id;
    uint public immutable descriptor;
    bytes private nested;
    event Processed(uint amount);
    error Rejected();

    constructor(uint logFlags, uint8 flags) Runtime(0, address(0)) {
        (id, descriptor) = command("run", Specs.Balance, Specs.AssetAmount, Specs.Balance, logFlags | flags);
    }

    function enforceCaller(address caller) internal pure override returns (address) { return caller; }

    function setNested(bytes calldata context) external { nested = context; }

    function run(bytes calldata context) external payable returns (bytes memory, uint) {
        return runCommand(id, descriptor, context, process);
    }

    function underallocated(bytes calldata context) external payable returns (bytes memory output, bool aliases) {
        Execution memory exec;
        exec.openContext(descriptor, msg.value, context, 0, 1);
        while (exec.more()) process(exec);
        uint abs = Encoder.pos(exec.buffer, exec.outputOffset());
        output = exec.finish(id, descriptor);
        aliases = Encoder.pos(output, 0) == abs;
        bytes32 digest = keccak256(output);
        bytes memory neighbor = abi.encode(exec.account, uint(0xabcdef));
        require(neighbor.length == 64 && keccak256(output) == digest);
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
