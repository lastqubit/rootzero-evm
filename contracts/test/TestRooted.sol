// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;
import {Keys, Specs, Sizes, Headers, Schemas, Encoder, Blocks, Cursors, Execution, Executions, Logs} from "../Codec.sol";

contract TestRooted {
    function layoutRooted() external pure returns (bytes4, uint, uint, uint, string memory) {
        return (Keys.Rooted, Specs.Rooted, Headers.Rooted, Sizes.Rooted, Schemas.Rooted);
    }
    function encode(bytes32 account, uint deadline, uint value, uint capacity)
        external pure returns (bytes memory created, bytes memory written, bytes memory output)
    {
        created = Encoder.createRooted(account, deadline, value);
        (bytes memory buffer, uint cur) = Encoder.init(capacity);
        (buffer, cur) = Encoder.writeRooted(cur, buffer, account, deadline, value);
        written = Encoder.finish(cur, buffer);
        Execution memory exec;
        (exec.buffer, exec.output) = Encoder.init(capacity);
        Executions.outputRooted(exec, account, deadline, value);
        output = Executions.finish(exec);
    }
    function decode(bytes calldata source, uint size, bool execution)
        external pure returns (bytes32 account, uint deadline, uint value, uint consumed, uint remaining)
    {
        uint abs = Cursors.base(source);
        uint cur = Cursors.create(abs, abs + size);
        if (execution) {
            Execution memory exec;
            exec.input = cur;
            (account, deadline, value) = Executions.unpackRooted(exec);
            cur = exec.input;
        } else (account, deadline, value, cur) = Blocks.unpackRooted(cur);
        consumed = Cursors.position(cur) - abs;
        remaining = Cursors.length(cur);
    }
    function emitRooted(uint codes, bytes32 account, uint deadline, uint value) external {
        Logs.rooted(account, deadline, value, codes);
    }
}
