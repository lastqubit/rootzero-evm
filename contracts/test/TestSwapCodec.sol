// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

import {Blocks, Encoder, Cursors, Keys, Specs, Sizes, Schemas, Execution, Executions} from "../Codec.sol";

contract TestSwapCodec {
    function describeBlock() external pure returns (bytes4, uint, uint, string memory) {
        return (Keys.Swap, Specs.Swap, Sizes.Swap, Schemas.Swap);
    }

    function encode(bytes32 asset, uint amount, bytes calldata hops, bytes calldata list, uint capacity, uint mode)
        external pure returns (bytes memory)
    {
        Execution memory exec;
        (exec.buffer, exec.output) = Encoder.init(capacity);
        if (mode == 0) (exec.buffer, exec.output) = Encoder.writeSwap(exec.output, exec.buffer, asset, amount, Cursors.wrap(list));
        else if (mode == 1) (exec.buffer, exec.output) = Encoder.writeSwapWrap(exec.output, exec.buffer, asset, amount, bytes(hops));
        else if (mode == 2) (exec.buffer, exec.output) = Encoder.writeSwapWrap(exec.output, exec.buffer, asset, amount, Cursors.wrap(hops));
        else if (mode == 3) Executions.outputSwap(exec, asset, amount, bytes(hops));
        else if (mode == 4) Executions.outputSwap(exec, asset, amount, Cursors.wrap(list));
        else Executions.outputSwapWrap(exec, asset, amount, Cursors.wrap(hops));
        return Executions.finish(exec);
    }

    function decode(bytes calldata source, uint size, uint offset, bool execution)
        external pure returns (bytes32 asset, uint amount, bytes calldata hops, uint next, uint metadata)
    {
        require(size <= source.length);
        uint base = Cursors.base(source);
        uint cur = (base + offset) | ((base + size) << 32) | (uint(0xa5) << 64);
        uint hopsCur;
        if (execution) {
            Execution memory exec;
            exec.input = cur;
            (asset, amount, hopsCur) = Executions.unpackSwap(exec);
            cur = exec.input;
        } else {
            (asset, amount, hopsCur, cur) = Blocks.unpackSwap(cur);
        }
        require(hopsCur >> 64 == 0);
        hops = Blocks.toBytes(hopsCur);
        next = Cursors.position(cur) - base;
        metadata = cur >> 64;
    }
}
