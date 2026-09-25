// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

import {Cur, Cursors, Decoders, Execution, Executions, Specs} from "../Codec.sol";

contract TestTextUnpackers {
    using Decoders for Cur;
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
            uint spec = kind == 0 ? Specs.String : kind == 1 ? Specs.Label : Specs.Schema;
            exec.openInput(Executions.describe(0, spec, 0, 0), 0, source);
            if (kind == 0) text = exec.unpackString();
            else if (kind == 1) {
                bytes32 namespace;
                (namespace, text) = exec.unpackLabel();
                first = uint(namespace);
            } else (first, text) = exec.unpackSchema();
            consumed = exec.absolute() - base;
        } else {
            Cur memory cur = Decoders.open(source);
            if (kind == 0) text = cur.unpackString();
            else if (kind == 1) {
                bytes32 namespace;
                (namespace, text) = cur.unpackLabel();
                first = uint(namespace);
            } else (first, text) = cur.unpackSchema();
            consumed = Cursors.position(cur.state) - base;
        }
    }
}
