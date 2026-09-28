// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;
import {Blocks} from "../codec/Blocks.sol";

contract TestCursorRunFixed {
    function validate(bytes calldata source, uint offset, uint length, uint metadata, uint expected)
        external pure returns (uint cur)
    {
        require(length <= source.length && offset <= source.length);
        uint abs;
        assembly ("memory-safe") { abs := source.offset }
        cur = (abs + offset) | ((abs + length) << 32) | (metadata & ~uint(type(uint64).max));
        Blocks.expectRunFixed(cur, expected);
    }
}
