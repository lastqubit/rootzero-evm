// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;
import {LegacyBlocks} from "./LegacyBlocks.sol";
import {LegacyMemory} from "./LegacyMemory.sol";

import {Cursors} from "../utils/Cursors.sol";
import {Blocks} from "../codec/Blocks.sol";
import {PositionConstraints, Position, Specs} from "../Codec.sol";
import {Execution, Executions} from "../execution/Execution.sol";
import {Sizes} from "../codec/Specs.sol";
import {Schemas} from "../codec/Schema.sol";

contract TestPositionConstraints {
    using Executions for Execution;

    function metadata() external pure returns (uint, uint, string memory) {
        return (Specs.PositionConstraints, Sizes.PositionConstraints, Schemas.PositionConstraints);
    }

    function checkExecution(bytes calldata input, Position memory position) external pure returns (PositionConstraints memory) {
        Execution memory exec;
        exec.openInput(Executions.describe(Specs.Empty, Specs.PositionConstraints, Specs.Empty), 0, input);
        exec.expectPositionConstraints(position);
        return exec.unpackPositionConstraints();
    }

    function checkDirect(bytes calldata input, uint offset, Position memory position) external pure returns (Position memory) {
        uint abs;
        assembly ("memory-safe") { abs := input.offset }
        require(offset <= input.length && input.length - offset >= Sizes.PositionConstraints);
        LegacyBlocks.expectPositionConstraints(abs + offset, position);
        return position;
    }

    function decode(bytes calldata input) external pure returns (PositionConstraints memory) {
        uint cur = Cursors.wrap(input);
        (PositionConstraints memory value,) = Blocks.unpackPositionConstraints(cur);
        return value;
    }

    function decodeMemory(bytes memory input) external pure returns (PositionConstraints[] memory values) {
        (uint abs, uint end) = LegacyMemory.bounds(input, Sizes.PositionConstraints);
        values = new PositionConstraints[](input.length / Sizes.PositionConstraints);
        uint i;
        while (abs < end) {
            values[i++] = LegacyMemory.unpackPositionConstraints(abs);
            abs += Sizes.PositionConstraints;
        }
    }

    function execute(bytes calldata context) external pure returns (bytes32[] memory values) {
        Execution memory exec;
        exec.openContext(Executions.describe(Specs.Position, Specs.PositionConstraints, Specs.Empty), 0, context);
        values = new bytes32[](Blocks.length(exec.input) / Sizes.PositionConstraints * 4);
        uint i;
        while (exec.more()) {
            exec.unpackPosition();
            PositionConstraints memory value = exec.unpackPositionConstraints();
            values[i++] = value.asset;
            values[i++] = bytes32(value.amount);
            values[i++] = value.liability;
            values[i++] = bytes32(value.debt);
        }
    }
}
