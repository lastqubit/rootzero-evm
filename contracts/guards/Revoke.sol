// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;
import {Logs} from "../codec/Logs.sol";

import {GuardBase} from "./Base.sol";
import {Specs} from "../Codec.sol";
import {AllowanceHook} from "../commands/admin/Allowance.sol";
import {DenyAssetHook} from "../commands/admin/Asset.sol";
import {NodeAccess} from "../core/Access.sol";
import {Execution, Executions} from "../execution/Execution.sol";
using Executions for Execution;

/// @title Revoke
/// @notice Guardian action that quickly revokes authorization from a list of node IDs.
/// Each NODE block in the input is deauthorized on the host.
/// Only callable by active guardian addresses.
abstract contract Revoke is NodeAccess, GuardBase {
    uint private immutable descriptor;
    uint private immutable id;

    constructor() {
        (id, descriptor) = guard("revoke", Specs.Node, 0);
    }

    /// @notice Revoke every NODE block in `input` as the active guardian.
    /// @dev Node mutation hooks publish Access events for authorization changes.
    function revoke(bytes calldata input) external onlyGuardian {
        runGuard(id, descriptor, input, revokeOne);
    }

    function revokeOne(Execution memory exec) private {
        uint node = exec.unpackNode();
        setAccess(node, false);
    }
}

/// @title RevokeAllowance
/// @notice Guardian action that revokes host-scoped asset allowances.
/// @dev Opt-in guard. Hosts expose it by inheriting this contract and implementing AllowanceHook.
abstract contract RevokeAllowance is GuardBase, AllowanceHook {
    uint private immutable descriptor;
    uint private immutable id;

    constructor() {
        (id, descriptor) = guard("revokeAllowance", Specs.HostAsset, Logs.Input);
    }

    /// @notice Revoke every HOST_ASSET allowance in `input` as the active guardian.
    /// @dev Logs INPUT after hooks; each allowance is set to zero.
    function revokeAllowance(bytes calldata input) external onlyGuardian {
        runGuard(id, descriptor, input, revokeAllowanceOne);
    }

    function revokeAllowanceOne(Execution memory exec) private {
        (uint peer, bytes32 asset) = exec.unpackHostAsset();
        allowance(peer, asset, 0);
    }
}

/// @title RevokeAsset
/// @notice Guardian action that denies assets through the host's existing asset hook.
/// @dev Opt-in guard. Hosts expose it by inheriting this contract and implementing DenyAssetHook.
abstract contract RevokeAsset is GuardBase, DenyAssetHook {
    uint private immutable descriptor;
    uint private immutable id;

    constructor() {
        (id, descriptor) = guard("revokeAsset", Specs.Asset, Logs.Input);
    }

    /// @notice Deny every ASSET block in `input` as the active guardian.
    /// @dev Logs INPUT after the asset hooks.
    function revokeAsset(bytes calldata input) external onlyGuardian {
        runGuard(id, descriptor, input, revokeAssetOne);
    }

    function revokeAssetOne(Execution memory exec) private {
        bytes32 asset = exec.unpackAsset();
        denyAsset(asset);
    }
}
