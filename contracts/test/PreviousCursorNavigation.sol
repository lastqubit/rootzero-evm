// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;
import {OutOfBounds} from "../utils/Errors.sol";
// Frozen baseline for differential benchmarks.
library PreviousCursorNavigation {
    function advance(uint cur, uint amount) internal pure returns (uint updated) {
        uint pos = uint32(cur);
        uint end = uint32(cur >> 32);
        if (amount > end - pos) revert OutOfBounds();
        updated = cur + amount;
    }
    function consume(uint cur, uint amount) internal pure returns (uint updated, uint abs) {
        abs = uint32(cur);
        uint end = uint32(cur >> 32);
        if (amount > end - abs) revert OutOfBounds();
        updated = cur + amount;
    }
}
