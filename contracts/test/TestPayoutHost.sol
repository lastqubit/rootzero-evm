// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

import {Host} from "../core/Host.sol";
import {CreatePayout} from "../commands/Payout.sol";

/// @dev Minimal payout host: only `createPayout`, called by its commander as an external step.
contract TestPayoutHost is Host, CreatePayout {
    constructor(uint cmdr) Host(0, "TestPayoutHost", address(0)) {
        if (cmdr != 0) setTrust(cmdr, true);
    }
}
