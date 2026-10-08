// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;
import {PreviousNamingBlocks, PreviousNamingExecutions} from "./PreviousNaming.sol";

import {Blocks, Cursors, Execution, Executions, Specs} from "../Codec.sol";

contract TestTextUnpackers {
    using Executions for Execution;

    // Keep data beyond the logical source available to distinguish cursor
    // containment from the compiler's physical calldata-copy check.
    function decode(uint kind, bool execution, bytes calldata data, uint length)
        external pure returns (uint first, string memory text, uint consumed)
    {
        bytes calldata source = data[:length];
        uint base;
        assembly ("memory-safe") { base := source.offset }
        if (execution) {
            Execution memory exec;
            uint spec = kind == 0 ? Specs.String : kind == 1 ? (uint(bytes32(bytes4(keccak256("#label")))) | (uint(40) << 192) | (uint(256) << 128)) : Specs.Schema;
            exec.openInput(Executions.describe(0, spec, 0), 0, source);
            uint textCur;
            if (kind == 0) textCur = exec.unpackString();
            else if (kind == 1) {
                bytes32 namespace;
                (namespace, textCur) = PreviousNamingExecutions.unpackLabel(exec);
                first = uint(namespace);
            } else (first, textCur) = exec.unpackSchema();
            text = Blocks.toString(textCur);
            consumed = uint32(exec.input) - base;
        } else {
            uint cur = Cursors.wrap(source);
            uint textCur;
            if (kind == 0) (textCur, cur) = Blocks.unpackString(cur);
            else if (kind == 1) {
                bytes32 namespace;
                (namespace, textCur, cur) = PreviousNamingBlocks.unpackLabel(cur);
                first = uint(namespace);
            } else (first, textCur, cur) = Blocks.unpackSchema(cur);
            text = Blocks.toString(textCur);
            consumed = Cursors.position(cur) - base;
        }
    }
}
