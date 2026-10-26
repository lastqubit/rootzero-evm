// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

import {Blocks, Encoder, Cursors, Keys, Specs, Sizes, Headers, Schemas, Execution, Executions} from "../Codec.sol";
import {Execute} from "../codec/Execute.sol";

contract TestTrustBlock {
    function describeBlock() external pure returns (bytes4 key, uint spec, uint header, uint size, string memory schema) {
        return (Keys.Trust, Specs.Trust, Headers.Trust, Sizes.Trust, Schemas.Trust);
    }

    function encode(uint id, uint capacity) external pure returns (
        bytes memory created, bytes memory written, bytes memory executed
    ) {
        created = Encoder.createTrust(id);
        (bytes memory buffer, uint cur) = Encoder.init(capacity);
        (buffer, cur) = Encoder.writeTrust(cur, buffer, id);
        written = Encoder.finish(cur, buffer);
        Execution memory exec;
        (exec.buffer, exec.output) = Encoder.init(capacity);
        Executions.outputTrust(exec, id);
        executed = Executions.finish(exec);
    }

    /// @dev mode 0: Blocks cursor; 1: Execution state lane; 2: Execute absolute calldata.
    function decode(bytes calldata source, uint size, uint mode) external pure returns (
        uint id, uint consumed, uint remaining
    ) {
        uint abs = Cursors.base(source);
        uint cur = Cursors.create(abs, abs + size);
        if (mode == 1) {
            Execution memory exec;
            exec.state = cur;
            id = Executions.unpackTrust(exec);
            cur = exec.state;
        } else if (mode == 2) {
            (uint start,) = Execute.bounds(cur, 40);
            id = Execute.unpackTrust(start);
            cur = Cursors.create(start + 40, abs + size);
        } else {
            (id, cur) = Blocks.unpackTrust(cur);
        }
        consumed = Cursors.position(cur) - abs;
        remaining = Cursors.length(cur);
    }

    /// @dev Checks one TRUST against `id`; mode 0: Blocks cursor, 1: Execution state lane.
    function expectId(bytes calldata source, uint id, uint mode) external pure returns (uint consumed, uint remaining) {
        uint abs = Cursors.base(source);
        uint cur = Cursors.create(abs, abs + source.length);
        if (mode == 1) {
            Execution memory exec;
            exec.state = cur;
            Executions.expectTrust(exec, id);
            cur = exec.state;
        } else {
            cur = Blocks.expectTrust(cur, id);
        }
        consumed = Cursors.position(cur) - abs;
        remaining = Cursors.length(cur);
    }

    /// @dev Execution reads TRUST from state only: a TRUST block in input is not consumed.
    function stateOnly(bytes calldata source) external pure returns (uint id) {
        Execution memory exec;
        exec.input = Cursors.create(Cursors.base(source), Cursors.base(source) + source.length);
        return Executions.unpackTrust(exec);
    }
}
