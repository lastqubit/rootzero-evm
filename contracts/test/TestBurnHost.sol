// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

import { Host } from "../core/Host.sol";
import { Burn } from "../commands/Burn.sol";

contract TestBurnHost is Host, Burn {
    event BurnCalled(bytes32 account, bytes32 asset, uint amount);

    constructor(uint cmdr)
        Host(0)
        Burn()
    {
        if (cmdr != 0) authorizeNode(cmdr);
    }

    function burn(bytes32 account, bytes32 asset, uint amount)
        internal override
        returns (uint)
    {
        emit BurnCalled(account, asset, amount);
        return amount;
    }

    function getAdminAccount() external view returns (bytes32) { return admin; }
}



