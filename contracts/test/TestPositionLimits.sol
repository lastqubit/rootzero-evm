// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

import {Blocks, Cur, Decoders, Position, Specs} from "../Codec.sol";
import {Execution, Executions} from "../execution/Execution.sol";

import {Sizes} from "../codec/Specs.sol";
import {Schemas} from "../codec/Schema.sol";

contract TestPositionLimits {
    using Decoders for Cur;

    using Executions for Execution;

    function metadata() external pure returns (uint, uint, string memory) {
        return (Specs.PositionLimits, Sizes.PositionLimits, Schemas.PositionLimits);
    }



    function checkExecution(bytes calldata input, Position memory position) external pure returns (bytes32 asset, uint minAmount, bytes32 liability, uint maxDebt) {
        Execution memory exec;
        exec.openInput(Executions.describe(Specs.Empty, Specs.PositionLimits, Specs.Empty, 0), 0, input);
        exec.expectPositionLimits(position);
        return exec.unpackPositionLimits();
    }

    function checkDirect(bytes calldata input, uint offset, Position memory position) external pure returns (Position memory) {
        uint abs;
        assembly ("memory-safe") { abs := input.offset }
        require(offset <= input.length && input.length - offset >= Sizes.PositionLimits);
        Blocks.expectPositionLimits(abs + offset, position);
        return position;
    }






    function decode(bytes calldata input) external pure returns (bytes32 asset, uint minAmount, bytes32 liability, uint maxDebt) {
        Cur memory cur = Decoders.open(input);
        return cur.unpackPositionLimits();
    }

    function execute(bytes calldata context) external pure returns (bytes32[] memory values) {
        Execution memory exec;
        exec.openContext(Executions.describe(Specs.Position, Specs.PositionLimits, Specs.Empty, 0), 0, context);
        values = new bytes32[](exec.rawInput().length / Sizes.PositionLimits * 4);
        uint i;
        while (exec.more()) {
            exec.unpackPosition();
            (bytes32 asset, uint minAmount, bytes32 liability, uint maxDebt) = exec.unpackPositionLimits();
            values[i++] = asset;
            values[i++] = bytes32(minAmount);
            values[i++] = liability;
            values[i++] = bytes32(maxDebt);
        }
    }
}
