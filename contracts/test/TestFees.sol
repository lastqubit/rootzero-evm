// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

import {Fees} from "../Utils.sol";

contract TestFees {
    function calculate(uint amount, int16 bps, uint limit) external pure returns (uint) {
        return Fees.calculate(amount, bps, limit);
    }

    function deductible(uint amount, uint16 bps, uint limit) external pure returns (uint) {
        return Fees.deductible(amount, bps, limit);
    }

    function addable(uint amount, uint16 bps, uint limit) external pure returns (uint) {
        return Fees.addable(amount, bps, limit);
    }
}
