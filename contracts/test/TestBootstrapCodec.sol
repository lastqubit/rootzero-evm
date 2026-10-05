// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;
import {Encoder, Blocks, Cursors, Specs} from "../Codec.sol";
import {Schemas} from "../codec/Schema.sol";
import {Execution, Executions} from "../execution/Execution.sol";

contract TestBootstrapCodec {
    function catalog() external pure returns (uint, string memory) {
        return (Specs.Bootstrap, Schemas.Bootstrap);
    }
    function create(uint budget, bytes memory balances) external pure returns (bytes memory) {
        return Encoder.createBootstrap(budget, balances);
    }
    function unpack(bytes calldata data, uint length, bool execution)
        external pure returns (uint budget, bytes memory balances, uint remaining, uint metadata)
    {
        require(length <= data.length);
        uint cur = Cursors.wrap(data[:length]) | (uint(0xa5) << 64);
        uint balancesCur;
        if (execution) {
            Execution memory exec;
            exec.input = cur;
            (budget, balancesCur) = Executions.unpackBootstrap(exec);
            cur = exec.input;
        } else {
            (budget, balancesCur, cur) = Blocks.unpackBootstrap(cur);
        }
        assert(balancesCur >> 64 == 0);
        balances = Blocks.toBytes(balancesCur);
        remaining = Cursors.length(cur);
        metadata = cur >> 64;
    }

    function unpackExact(bytes calldata data, uint length)
        external pure returns (uint budget, bytes memory balances)
    {
        require(length <= data.length);
        uint cur = Cursors.wrap(data[:length]) | (uint(0xa5) << 64);
        uint balancesCur;
        (budget, balancesCur) = Blocks.unpackBootstrapExact(cur);
        assert(balancesCur >> 64 == 0);
        balances = Blocks.toBytes(balancesCur);
    }

}
