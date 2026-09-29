// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

import {Blocks, Encoder, Cursors, Keys, Specs, Sizes, Headers, Schemas, Execution, Executions} from "../Codec.sol";

contract TestEntityBlock {
    function describeBlock() external pure returns (bytes4 key, uint spec, uint header, uint size, string memory schema) {
        return (Keys.Entity, Specs.Entity, Headers.Entity, Sizes.Entity, Schemas.Entity);
    }

    function encode(uint entity, uint capacity) external pure returns (
        bytes memory created, bytes memory written, bytes memory executed
    ) {
        created = Encoder.createEntity(entity);
        (bytes memory buffer, uint cur) = Encoder.init(capacity);
        (buffer, cur) = Encoder.writeEntity(cur, buffer, entity);
        written = Encoder.finish(cur, buffer);
        Execution memory exec;
        (exec.buffer, exec.output) = Encoder.init(capacity);
        Executions.outputEntity(exec, entity);
        executed = Executions.finish(exec);
    }

    function decode(bytes calldata source, uint size, bool execution) external pure returns (
        uint entity, uint consumed, uint remaining
    ) {
        uint abs = Cursors.base(source);
        uint cur = Cursors.create(abs, abs + size);
        if (execution) {
            Execution memory exec;
            exec.input = cur;
            entity = Executions.unpackEntity(exec);
            cur = exec.input;
        } else {
            (entity, cur) = Blocks.unpackEntity(cur);
        }
        consumed = Cursors.position(cur) - abs;
        remaining = Cursors.length(cur);
    }
}
