// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;
import {Encoder, Blocks, Cursors, Specs} from "../Codec.sol";
import {Schemas} from "../codec/Schema.sol";
import {Execution, Executions} from "../execution/Execution.sol";

contract TestVouchCodec {
    function catalog() external pure returns (uint, string memory) {
        return (Specs.Vouch, Schemas.Vouch);
    }
    function create(uint budget, bytes memory ids) external pure returns (bytes memory) {
        return Encoder.createVouch(budget, ids);
    }
    function unpack(bytes calldata data, uint length, bool execution)
        external pure returns (uint budget, bytes memory ids, uint remaining, uint metadata)
    {
        require(length <= data.length);
        uint cur = Cursors.wrap(data[:length]) | (uint(0xa5) << 64);
        uint idsCur;
        if (execution) {
            Execution memory exec;
            exec.input = cur;
            (budget, idsCur) = Executions.unpackVouch(exec);
            cur = exec.input;
        } else {
            (budget, idsCur, cur) = Blocks.unpackVouch(cur);
        }
        assert(idsCur >> 64 == 0);
        ids = Blocks.toBytes(idsCur);
        remaining = Cursors.length(cur);
        metadata = cur >> 64;
    }
}
