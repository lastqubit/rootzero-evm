// SPDX-License-Identifier: MIT
pragma solidity ^0.8.33;

// Example 1: Minimal Host
//
// CommandHost supplies only commander access and deployment-time introduction.
// The inherited command module supplies CommandBase and its endpoint.
//
// This host deliberately has no admin commands, node registry, guardians,
// inbound introduction endpoint, generic execution, or receive function.

import { CommandHost } from "../contracts/Core.sol";
import { DebitAccount } from "../contracts/Endpoints.sol";

contract ExampleHost is CommandHost, DebitAccount {
    mapping(bytes32 account => mapping(bytes32 asset => uint amount)) internal balances;

    // commander must be nonzero and identifies the only native caller allowed to invoke debitAccount.
    // If it is a contract, it must accept introduce(uint,uint,string) during deployment.
    constructor(uint commander) CommandHost(commander, "1-Host") {}

    function debitAccount(bytes32 account, bytes32 asset, uint amount) internal override {
        balances[account][asset] -= amount;
    }
}



