// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

import {Logs} from "../Codec.sol";

contract TestLogFlags {
    function logFlags() external pure returns (uint[4] memory) {
        return [Logs.Execution, Logs.State, Logs.Input, Logs.Output];
    }

}
