// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

import {CommandBase} from "../commands/Base.sol";
import {CommandHost} from "../core/Host.sol";

abstract contract TestPingCommand is CommandBase {
    function ping() external view onlyCommand returns (bool) {
        return true;
    }
}

contract TestMinimalCommandHost is CommandHost, TestPingCommand {
    constructor(uint cmdr) CommandHost(cmdr, "TestMinimalCommandHost") {}
}
