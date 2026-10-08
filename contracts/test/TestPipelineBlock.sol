// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;
import {Keys, Specs, Sizes, Headers, Schemas, Encoder, Blocks, Cursors, Execution, Executions} from "../Codec.sol";

contract TestPipelineBlock {
    function layoutPipeline() external pure returns (bytes4, uint, uint, uint, string memory) {
        return (Keys.Pipeline, Specs.Pipeline, Headers.Pipeline, Sizes.Pipeline, Schemas.Pipeline);
    }
    function encode(bytes32 account, uint budget, uint capacity)
        external pure returns (bytes memory created, bytes memory written, bytes memory output)
    {
        created = Encoder.createPipeline(account, budget);
        (bytes memory buffer, uint cur) = Encoder.init(capacity);
        (buffer, cur) = Encoder.writePipeline(cur, buffer, account, budget);
        written = Encoder.finish(cur, buffer);
        Execution memory exec;
        (exec.buffer, exec.output) = Encoder.init(capacity);
        Executions.outputPipeline(exec, account, budget);
        output = Executions.finish(exec);
    }
    function decode(bytes calldata source, uint size, bool execution)
        external pure returns (bytes32 account, uint budget, uint consumed, uint remaining)
    {
        uint abs = Cursors.base(source);
        uint cur = Cursors.create(abs, abs + size);
        if (execution) {
            Execution memory exec;
            exec.input = cur;
            (account, budget) = Executions.unpackPipeline(exec);
            cur = exec.input;
        } else (account, budget, cur) = Blocks.unpackPipeline(cur);
        consumed = Cursors.position(cur) - abs;
        remaining = Cursors.length(cur);
    }
}
