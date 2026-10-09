// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

import {CommandBase, Execution, Executions} from "../commands/Base.sol";
import {Runtime} from "../core/Runtime.sol";
import {Specs} from "../codec/Specs.sol";
import {Schemas} from "../codec/Schema.sol";

contract TestLaneAnnotation is CommandBase {
    uint public immutable commandId;
    uint public immutable descriptor;
    uint public immutable inputLane;

    constructor() Runtime(0, address(0)) {
        inputLane = lane("#amount[2] as (first, second)", 1, Specs.Amount);
        (commandId, descriptor) = command("grouped", Specs.Empty, inputLane, Specs.Amount, 0);
    }

    function publish(string memory body, uint32 key, uint spec) external returns (uint) {
        return lane(body, key, spec);
    }
    function publishNamed(string memory body, string memory key, uint spec) external returns (uint) {
        return lane(body, key, spec);
    }
    function schemaExact(string memory body, string memory key, uint32 size) external returns (uint) {
        return schema(body, key, size);
    }
    function schemaRange(string memory body, string memory key, uint32 min, uint32 max, uint32 hint)
        external returns (uint)
    {
        return schema(body, key, min, max, hint);
    }
    function publishSchema(string memory body, uint spec) external returns (uint) { return schema(body, spec); }
    function catalog() external pure returns (uint, string memory) { return (Specs.Lane, Schemas.Lane); }
    function describe(uint state, uint input, uint output) external pure returns (uint) {
        return Executions.describe(state, input, output);
    }
    function copy(bytes calldata input, uint inputSpec, uint outputSpec)
        external pure returns (uint capacity, bytes memory output)
    {
        Execution memory exec;
        Executions.openInput(exec, Executions.describe(0, inputSpec, outputSpec), 0, input);
        capacity = uint32(exec.output >> 32);
        while (Executions.more(exec)) {
            uint first = Executions.unpackAmount(exec);
            uint second = Executions.unpackAmount(exec);
            Executions.outputAmount(exec, first);
            Executions.outputAmount(exec, second);
        }
        output = Executions.finish(exec);
    }
    function enforceCaller(address caller) internal pure override returns (address) { return caller; }
}
