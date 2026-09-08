// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

import {Blocks, Limits, Cur, Decoders, Specs, Writer, Writers} from "../Codec.sol";
import {Memory} from "../codec/Blocks.sol";
import {Sizes} from "../codec/Specs.sol";
import {Schemas} from "../codec/Schema.sol";
import {Execution, Executions} from "../execution/Execution.sol";

contract TestLimits {
    using Decoders for Cur;
    using Writers for Writer;
    using Executions for Execution;

    function metadata() external pure returns (uint, uint, string memory) {
        return (Specs.Limits, Sizes.Limits, Schemas.Limits);
    }

    function create(uint amount, uint debt) external pure returns (bytes memory) {
        return Blocks.createLimits(amount, debt);
    }

    function write(uint[] calldata values) external pure returns (bytes memory) {
        Writer memory writer = Writers.init(Specs.Limits, 1);
        for (uint i; i < values.length; i += 2) writer.appendLimits(values[i], values[i + 1]);
        return writer.finish();
    }

    function decode(bytes calldata input) external pure returns (uint amount, uint debt) {
        Cur memory cur = Decoders.open(input);
        return cur.unpackLimits();
    }

    function check(bytes calldata input, uint amount, uint debt, bool execution)
        external pure returns (uint nextAmount, uint nextDebt)
    {
        if (execution) {
            Execution memory exec;
            exec.open(Executions.describe(Specs.Empty, Specs.Limits, Specs.Empty, 0), 0, 0, input[:0], input);
            exec.requireLimits(amount, debt);
            return exec.unpackLimits();
        }
        Cur memory cur = Decoders.open(input);
        cur.requireLimits(amount, debt);
        return cur.unpackLimits();
    }

    function roundtrip(bytes calldata input, bool memorySource) external pure returns (bytes memory) {
        Writer memory writer = Writers.init(Specs.Limits, 1);
        if (memorySource) {
            (uint abs, uint end) = Memory.bounds(input, Sizes.Limits);
            while (abs < end) {
                (uint amount, uint debt) = Memory.unpackLimits(abs);
                writer.appendLimits(amount, debt);
                abs += Sizes.Limits;
            }
        } else {
            Cur memory cur = Decoders.open(input);
            while (cur.more()) {
                (uint amount, uint debt) = cur.unpackLimits();
                writer.appendLimits(amount, debt);
            }
        }
        return writer.finish();
    }

    function structured(bytes calldata input, uint mode) external pure returns (bytes memory) {
        if (mode == 2) {
            Execution memory exec;
            exec.open(Executions.describe(Specs.Empty, Specs.Limits, Specs.Limits, 0), 0, 0, input[:0], input);
            while (exec.more()) exec.outputLimits(exec.unpackLimitsValue());
            return exec.finish();
        }
        Writer memory writer = Writers.init(Specs.Limits, 1);
        if (mode == 1) {
            (uint abs, uint end) = Memory.bounds(input, Sizes.Limits);
            while (abs < end) {
                writer.appendLimits(Memory.unpackLimitsValue(abs));
                abs += Sizes.Limits;
            }
        } else {
            Cur memory cur = Decoders.open(input);
            while (cur.more()) writer.appendLimits(cur.unpackLimitsValue());
        }
        return writer.finish();
    }

    function execute(bytes calldata input) external pure returns (bytes memory) {
        Execution memory exec;
        exec.open(Executions.describe(Specs.Empty, Specs.Limits, Specs.Limits, 0), 0, 0, input[:0], input);
        while (exec.more()) {
            (uint amount, uint debt) = exec.unpackLimits();
            exec.outputLimits(amount, debt);
        }
        return exec.finish();
    }
}
