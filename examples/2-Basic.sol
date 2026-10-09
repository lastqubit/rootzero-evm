// SPDX-License-Identifier: MIT
pragma solidity ^0.8.33;

// Example 2: Built-In Command (DebitAccount)
//
// The easiest way to add a command is to mix in a built-in command module and
// implement its hook. The module handles block parsing and response encoding;
// you only write the business logic specific to your app.
//
// DebitAccount:
//   - opens an execution over the ASSET_AMOUNT run in `input`
//   - calls `debitAccount` for each block in that run
//   - returns matching BALANCE blocks as the response

import { Host } from "../contracts/Core.sol";
import { DebitAccount } from "../contracts/Endpoints.sol";

contract ExampleHost is Host, DebitAccount {
    // Internal balance ledger: account -> asset -> amount
    mapping(bytes32 account => mapping(bytes32 asset => uint amount)) internal balances;

    constructor(uint rootzero) Host(rootzero, "2-Basic", address(0)) {}

    // debitAccount is the hook DebitAccount calls for each ASSET_AMOUNT block.
    // Implement this with whatever storage your app uses.
    function debitAccount(bytes32 account, bytes32 asset, uint amount) internal override {
        balances[account][asset] -= amount;
    }
}



