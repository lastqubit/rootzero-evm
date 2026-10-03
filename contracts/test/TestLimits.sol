// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;
import {LegacyBlocks} from "./LegacyBlocks.sol";
import {LegacyMemory} from "./LegacyMemory.sol";

import {Cursors} from "../utils/Cursors.sol";
import {Blocks} from "../codec/Blocks.sol";
import {Encoder} from "../codec/Encoder.sol";
import {Specs} from "../Codec.sol";

import {Sizes} from "../codec/Specs.sol";
import {Schemas} from "../codec/Schema.sol";
import {Execution, Executions} from "../execution/Execution.sol";
import {OutOfRange} from "../utils/Errors.sol";

contract TestLimits {
    using Executions for Execution;

    function metadata() external pure returns (uint, uint, string memory) {
        return (Specs.Limits, Sizes.Limits, Schemas.Limits);
    }

    function create(uint limits) external pure returns (bytes memory) {
        return LegacyBlocks.createLimits(limits);
    }

    function write(uint[] calldata values) external pure returns (bytes memory) {
        (bytes memory writerBuffer, uint writer) = Encoder.init(Specs.allocation(Specs.Limits, 1));
        for (uint i; i < values.length; i++) (writerBuffer, writer) = Encoder.writeLimits(writer, writerBuffer, values[i]);
        return Encoder.finish(writer, writerBuffer);
    }

    function decode(bytes calldata input) external pure returns (uint limits) {
        uint cur = Cursors.wrap(input);
        (limits,) = Blocks.unpackLimits(cur);
    }

    function check(bytes calldata input, uint amount, uint debt, bool execution)
        external pure returns (uint nextLimits)
    {
        if (execution) {
            Execution memory exec;
            exec.openInput(Executions.describe(Specs.Empty, Specs.Limits, Specs.Empty), 0, input);
            exec.expectLimits(amount, debt);
            return exec.unpackLimits();
        }
        uint cur = Cursors.wrap(input);
        (uint limits, uint nextCur) = Blocks.unpackLimits(cur);
        if (amount < limits >> 128 || debt > uint128(limits)) revert OutOfRange();
        (nextLimits,) = Blocks.unpackLimits(nextCur);
    }

    function roundtrip(bytes calldata input, bool memorySource) external pure returns (bytes memory) {
        (bytes memory writerBuffer, uint writer) = Encoder.init(Specs.allocation(Specs.Limits, 1));
        if (memorySource) {
            (uint abs, uint end) = LegacyMemory.bounds(input, Sizes.Limits);
            while (abs < end) {
                (writerBuffer, writer) = Encoder.writeLimits(writer, writerBuffer, LegacyMemory.unpackLimits(abs));
                abs += Sizes.Limits;
            }
        } else {
            uint cur = Cursors.wrap(input);
            while (Cursors.more(cur)) {
                (uint limits, uint nextCur) = Blocks.unpackLimits(cur);
                cur = nextCur;
                (writerBuffer, writer) = Encoder.writeLimits(writer, writerBuffer, limits);
            }
        }
        return Encoder.finish(writer, writerBuffer);
    }

    function execute(bytes calldata input) external pure returns (bytes memory) {
        Execution memory exec;
        exec.openInput(Executions.describe(Specs.Empty, Specs.Limits, Specs.Limits), 0, input);
        while (exec.more()) {
            exec.outputLimits(exec.unpackLimits());
        }
        return exec.finish();
    }
}
