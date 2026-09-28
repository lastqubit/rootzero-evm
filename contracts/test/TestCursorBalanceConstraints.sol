// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;
import {Blocks} from "../codec/Blocks.sol";
import {Headers} from "../codec/Headers.sol";

contract TestCursorBalanceConstraints {
    function check(bytes calldata source, uint offset, uint length, uint metadata, bytes32 asset, uint amount, bool deferred)
        external pure returns (uint nextCur, uint original)
    {
        require(offset <= source.length && length <= source.length);
        uint abs;
        assembly ("memory-safe") { abs := source.offset }
        original = (abs + offset) | ((abs + length) << 32) | (metadata & ~uint(type(uint64).max));
        if (deferred) {
            uint payloadCur;
            (payloadCur, nextCur) = Blocks.unpackFixed(original, Headers.BalanceConstraints);
            Blocks.checkBalanceConstraints(uint32(payloadCur), asset, amount);
        } else nextCur = Blocks.expectBalanceConstraints(original, asset, amount);
    }
    function scan(bytes calldata source, bytes32 asset, uint amount) external pure returns (uint count) {
        uint cur;
        assembly ("memory-safe") { cur := or(source.offset, shl(32, add(source.offset, source.length))) }
        while (uint32(cur) < uint32(cur >> 32)) {
            cur = Blocks.expectBalanceConstraints(cur, asset, amount);
            ++count;
        }
    }
}
