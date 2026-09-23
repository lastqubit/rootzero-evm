// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

import {Execution, Executions, CommandBase, HostAmount, Specs} from "./Base.sol";

using Executions for Execution;

/// @notice Shared allocation hook used by `Allocate`.
abstract contract AllocateHook {
    /// @notice Override to allocate a live balance into custody on a host.
    /// Called once per paired BALANCE state block and NODE input block.
    /// Implementations should perform only the custody side effect; output
    /// blocks are written by the caller.
    /// @param account Caller's account identifier.
    /// @param custody Host-scoped amount to allocate into custody.
    function allocate(bytes32 account, HostAmount memory custody) internal virtual;
}

/// @title Allocate
/// @notice Command that allocates BALANCE state to custody on requested hosts.
/// Each BALANCE state block is paired with one NODE input block at the same
/// position; the output is a matching CUSTODY state stream.
abstract contract Allocate is CommandBase, AllocateHook {
    uint private immutable descriptor;

    constructor() {
        (, descriptor) = command("allocate", Specs.Balance, Specs.Node, Specs.Custody, 0);
    }

    /// @notice Allocate BALANCE state blocks to matching NODE input blocks.
    /// @param context Command context carrying BALANCE state and matching NODE input.
    /// @return CUSTODY block stream matching the allocated balances.
    /// @return Zero native budget credit.
    function allocate(bytes calldata context) external onlyCommand returns (bytes memory, uint) {
        return runCommand(context, descriptor, allocateOne);
    }

    function allocateOne(Execution memory exec) private {
        HostAmount memory custody;
        custody.host = exec.unpackNode();
        (custody.asset, custody.amount) = exec.unpackBalance();
        allocate(exec.account, custody);
        exec.outputCustody(custody);
    }
}
