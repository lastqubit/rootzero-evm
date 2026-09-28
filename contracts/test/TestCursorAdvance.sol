// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;
import {Blocks} from "../codec/Blocks.sol";

contract TestCursorAdvance {
    function expectHeader(bytes calldata source, uint offset, uint expected) external pure {
        uint abs;
        assembly ("memory-safe") { abs := add(source.offset, offset) }
        Blocks.expectHeader(abs, expected);
    }

    function advance(uint cur, uint size) external pure returns (uint) {
        return Blocks.advance(cur, size);
    }
}
