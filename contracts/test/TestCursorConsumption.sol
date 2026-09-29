// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;
import {Cursors} from "../utils/Cursors.sol";
contract TestCursorConsumption {
    function take(uint cur, uint amount) external pure returns (uint sliceCur, uint nextCur) {
        return Cursors.take(cur, amount);
    }

    function expectEnd(uint cur) external pure { Cursors.expectEnd(cur); }
    function exhaust(uint cur) external pure returns (uint nextCur) {
        nextCur = Cursors.exhaust(cur);
        Cursors.expectEnd(nextCur);
    }
}
