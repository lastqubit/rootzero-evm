// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;
import {Logs} from "../codec/Logs.sol";

import {GuardBase} from "./Base.sol";
import {Specs} from "../Codec.sol";
import {AllowanceHook} from "../commands/admin/Allowance.sol";
import {TrustAccess} from "../core/Access.sol";
import {Execution, Executions} from "../execution/Execution.sol";
using Executions for Execution;

/// @title Revoke
/// @notice Guardian action that quickly removes a list of IDs from the host's trusted set.
/// Each ENTITY block in the input is untrusted, whatever its kind.
/// Only callable by active guardian addresses.
abstract contract Revoke is TrustAccess, GuardBase {
    uint private immutable descriptor;

    constructor() {
        (, descriptor) = guard("revoke", Specs.Entity, 0);
    }

    /// @notice Revoke every ENTITY block in `input` as the active guardian.
    /// @dev The trust hook publishes Trust records for changes.
    /// @param input ENTITY blocks to untrust.
    function revoke(bytes calldata input) external onlyGuardian {
        runGuard(descriptor, input, revokeOne);
    }

    /// @dev Decode one ID and untrust it.
    /// @param exec Execution containing the account, source cursors, output writer, and native-value budget.
    function revokeOne(Execution memory exec) private {
        setTrust(exec.unpackEntity(), false);
    }
}

/// @title RevokeAllowance
/// @notice Guardian action that revokes host-scoped asset allowances.
/// @dev Opt-in guard. Hosts expose it by inheriting this contract and implementing AllowanceHook.
abstract contract RevokeAllowance is GuardBase, AllowanceHook {
    uint private immutable descriptor;

    constructor() {
        (, descriptor) = guard("revokeAllowance", Specs.HostAsset, Logs.Input);
    }

    /// @notice Revoke every HOST_ASSET allowance in `input` as the active guardian.
    /// @dev Each allowance is set to zero. Hints callers to record INPUT.
    /// @param input HOST_ASSET blocks whose allowances are revoked.
    function revokeAllowance(bytes calldata input) external onlyGuardian {
        runGuard(descriptor, input, revokeAllowanceOne);
    }

    /// @dev Decode one host/asset pair and set its allowance to zero.
    /// @param exec Execution containing the account, source cursors, output writer, and native-value budget.
    function revokeAllowanceOne(Execution memory exec) private {
        (uint peer, bytes32 asset) = exec.unpackHostAsset();
        allowance(peer, asset, 0);
    }
}
