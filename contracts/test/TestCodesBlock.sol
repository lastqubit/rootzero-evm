// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

import {Blocks, Encoder, Cursors, Keys, Specs, Sizes, Headers, Schemas, Execution, Executions} from "../Codec.sol";

contract TestCodesBlock {
    function layout() external pure returns (bytes4 key, uint spec, uint header, uint size, string memory schema) {
        return (Keys.Codes, Specs.Codes, Headers.Codes, Sizes.Codes, Schemas.Codes);
    }

    function encode(uint codes, uint capacity) external pure returns (
        bytes memory created, bytes memory written, bytes memory executed
    ) {
        created = Encoder.createCodes(codes);
        (bytes memory buffer, uint cur) = Encoder.init(capacity);
        (buffer, cur) = Encoder.writeCodes(cur, buffer, codes);
        written = Encoder.finish(cur, buffer);
        Execution memory exec;
        (exec.buffer, exec.output) = Encoder.init(capacity);
        Executions.outputCodes(exec, codes);
        executed = Executions.finish(exec);
    }

    function decode(bytes calldata source, uint size, bool execution) external pure returns (
        uint codes, uint consumed, uint remaining
    ) {
        uint abs = Cursors.base(source);
        uint cur = Cursors.create(abs, abs + size);
        if (execution) {
            Execution memory exec;
            exec.input = cur;
            codes = Executions.unpackCodes(exec);
            cur = exec.input;
        } else {
            (codes, cur) = Blocks.unpackCodes(cur);
        }
        consumed = Cursors.position(cur) - abs;
        remaining = Cursors.length(cur);
    }
}
