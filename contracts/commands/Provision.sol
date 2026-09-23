// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

import {Execution, Executions, CommandBase, Flags, HostAmount, Specs} from "./Base.sol";
using Executions for Execution;

/// @notice Shared provision hook used by `Provision`.
abstract contract ProvisionHook {
    /// @notice Override to send or provision a custody value.
    /// Called once per provisioned asset. Implementations should perform only the
    /// side effect (e.g. transfer or record); output blocks are written by the caller.
    /// @param account Caller's account identifier.
    /// @param allocation Host-scoped amount to provision.
    function provision(bytes32 account, HostAmount memory allocation) internal virtual;
}

/// @notice Shared provision hook used by `ProvisionPayable`.
abstract contract ProvisionPayableHook {
    /// @notice Override to send or provision a custody value.
    /// Called once per provisioned asset. Implementations should perform only the
    /// side effect (e.g. transfer or record); output blocks are written by the caller.
    /// @param account Caller's account identifier.
    /// @param allocation Host-scoped amount to provision.
    /// @param funds Mutable execution used only for its remaining native-value budget.
    function provision(bytes32 account, HostAmount memory allocation, Execution memory funds) internal virtual;
}

/// @title Provision
/// @notice Command that provisions assets to peer hosts from ALLOCATION input blocks.
/// Each input block supplies the target host plus an asset amount; the output is a CUSTODY state stream.
abstract contract Provision is CommandBase, ProvisionHook {
    uint private immutable descriptor;

    constructor() {
        (, descriptor) = command("provision", Specs.Empty, Specs.Allocation, Specs.Custody, 0);
    }

    /// @notice Provision ALLOCATION input blocks and output matching CUSTODY state blocks.
    /// @param context Command context carrying the ALLOCATION input stream.
    /// @return CUSTODY block stream matching the provisioned allocations.
    /// @return Zero native budget credit.
    function provision(bytes calldata context) external onlyCommand returns (bytes memory, uint) {
        return runCommand(context, descriptor, provisionOne);
    }

    function provisionOne(Execution memory exec) private {
        HostAmount memory allocation = exec.unpackAllocationValue();
        provision(exec.account, allocation);
        exec.outputCustody(allocation);
    }
}

/// @title ProvisionPayable
/// @notice Command that provisions assets to peer hosts from ALLOCATION input blocks.
/// Each input block supplies the target host plus an asset amount; the output is a CUSTODY state stream.
/// The hook receives a mutable native-value budget drawn from `msg.value`.
abstract contract ProvisionPayable is CommandBase, ProvisionPayableHook {
    uint private immutable descriptor;

    constructor() {
        (, descriptor) = command("provisionPayable", Specs.Empty, Specs.Allocation, Specs.Custody, Flags.Funded);
    }

    /// @notice Provision ALLOCATION input blocks with access to a mutable native-value budget.
    /// @param context Command context carrying the ALLOCATION input stream.
    /// @return CUSTODY block stream matching the provisioned allocations.
    /// @return Native value to add to the caller's budget.
    function provisionPayable(bytes calldata context) external payable onlyCommand returns (bytes memory, uint) {
        return runCommand(context, descriptor, provisionPayableOne);
    }

    function provisionPayableOne(Execution memory exec) private {
        HostAmount memory allocation = exec.unpackAllocationValue();
        provision(exec.account, allocation, exec);
        exec.outputCustody(allocation);
    }
}
