// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

import {Blocks, Cur, Decoders, Specs, Writer, Writers} from "../Codec.sol";
import {Memory} from "../codec/Blocks.sol";
import {Sizes} from "../codec/Specs.sol";
import {Schemas} from "../codec/Schema.sol";
import {Execution, Executions} from "../execution/Execution.sol";

import {OutOfRange} from "../utils/Errors.sol";

contract TestLimits {
    using Decoders for Cur;
    using Writers for Writer;
    using Executions for Execution;

    function metadata() external pure returns (uint, uint, string memory) {
        return (Specs.Limits, Sizes.Limits, Schemas.Limits);
    }

    function create(uint limits) external pure returns (bytes memory) {
        return Blocks.createLimits(limits);
    }

    function write(uint[] calldata values) external pure returns (bytes memory) {
        Writer memory writer = Writers.init(Specs.Limits, 1);
        for (uint i; i < values.length; i++) writer.appendLimits(values[i]);
        return writer.finish();
    }

    function decode(bytes calldata input) external pure returns (uint limits) {
        Cur memory cur = Decoders.open(input);
        return cur.unpackLimits();
    }

    function check(bytes calldata input, uint amount, uint debt, bool execution)
        external pure returns (uint nextLimits)
    {
        if (execution) {
            Execution memory exec;
            exec.openInput(Executions.describe(Specs.Empty, Specs.Limits, Specs.Empty, 0), 0, input);
            exec.expectLimits(amount, debt);
            return exec.unpackLimits();
        }
        Cur memory cur = Decoders.open(input);
        uint limits = cur.unpackLimits();
        if (amount < limits >> 128 || debt > uint128(limits)) revert OutOfRange();
        return cur.unpackLimits();
    }

    function roundtrip(bytes calldata input, bool memorySource) external pure returns (bytes memory) {
        Writer memory writer = Writers.init(Specs.Limits, 1);
        if (memorySource) {
            (uint abs, uint end) = Memory.bounds(input, Sizes.Limits);
            while (abs < end) {
                writer.appendLimits(Memory.unpackLimits(abs));
                abs += Sizes.Limits;
            }
        } else {
            Cur memory cur = Decoders.open(input);
            while (cur.more()) {
                writer.appendLimits(cur.unpackLimits());
            }
        }
        return writer.finish();
    }

    function execute(bytes calldata input) external pure returns (bytes memory) {
        Execution memory exec;
        exec.openInput(Executions.describe(Specs.Empty, Specs.Limits, Specs.Limits, 0), 0, input);
        while (exec.more()) {
            exec.outputLimits(exec.unpackLimits());
        }
        return exec.finish();
    }
}
