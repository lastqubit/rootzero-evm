// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

import { Host } from "../core/Host.sol";
import { Deposit } from "../commands/Deposit.sol";
import { GetBalance } from "../queries/Balance.sol";

contract TestCompositeHost is Host, Deposit, GetBalance {
    constructor(uint cmdr)
        Host(0)
        Deposit()
        GetBalance()
    {
        if (cmdr != 0) authorizeNode(cmdr);
    }

    function deposit(bytes32 account, bytes32 asset, uint amount) internal pure override returns (uint) {
        account; asset;
        return amount;
    }

    function getBalance(bytes32 account, bytes32 asset) internal pure override returns (uint amount) {
        account; asset;
        return 0;
    }
}
