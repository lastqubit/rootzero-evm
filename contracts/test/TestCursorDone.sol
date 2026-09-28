// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;
import {Cursors} from "../utils/Cursors.sol";
import {UnexpectedInput} from "../utils/Errors.sol";
contract CursorDoneDirect {
    function done(uint cur) external pure returns (bool) { return uint32(cur) == uint32(cur >> 32); }
    function measure(uint cur) external view returns (uint used) {
        uint beforeGas = gasleft();
        if (!(uint32(cur) == uint32(cur >> 32))) revert UnexpectedInput();
        used = beforeGas - gasleft();
    }
}
contract CursorDoneShared {
    function done(uint cur) external pure returns (bool) { return Cursors.done(cur); }
    function measure(uint cur) external view returns (uint used) {
        uint beforeGas = gasleft();
        if (!(Cursors.done(cur))) revert UnexpectedInput();
        used = beforeGas - gasleft();
    }
}
contract CursorDoneGuardDirect {
    function check(uint cur) external pure { if (!(uint32(cur) == uint32(cur >> 32))) revert UnexpectedInput(); }
}
contract CursorDoneGuardShared {
    function check(uint cur) external pure { if (!(Cursors.done(cur))) revert UnexpectedInput(); }
}
