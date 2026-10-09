// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

import {Host} from "../core/Host.sol";

contract TestBareHost is Host {
    constructor(uint cmdr) Host(cmdr, "TestBareHost", address(0)) {}
}
