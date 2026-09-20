// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

import { AdminBase, Execution, Executions, Flags, Specs } from "./Base.sol";
using Executions for Execution;

/// @notice Hook implemented by hosts that allow assets.
abstract contract AllowAssetHook {
    /// @dev Override to allow a single asset.
    /// Called once per ASSET block in the input.
    /// @param asset Asset identifier.
    function allowAsset(bytes32 asset) internal virtual;
}

/// @notice Hook implemented by hosts that deny assets.
abstract contract DenyAssetHook {
    /// @dev Override to deny a single asset.
    /// Called once per ASSET block in the input.
    /// @param asset Asset identifier.
    function denyAsset(bytes32 asset) internal virtual;
}

/// @title AllowAsset
/// @notice Admin command that permits a list of assets via a virtual hook.
/// Each ASSET block in the input calls `allowAsset`. Only callable by the admin account.
abstract contract AllowAsset is AdminBase, AllowAssetHook {
    uint private immutable descriptor;

    constructor() {
        (, descriptor) = command("allowAsset", Specs.Empty, Specs.Asset, Specs.Empty, Flags.Admin);
    }

    /// @notice Allow each ASSET block in the admin input.
    /// @param context Admin command context carrying the ASSET input stream.
    /// @return Empty output state.
    /// @return Zero native budget credit.
    function allowAsset(
        bytes calldata context
    ) external returns (bytes memory, uint) {
        Execution memory exec = openAdminCommand(context, descriptor);

        while (exec.more()) {
            bytes32 asset = exec.unpackAsset();
            allowAsset(asset);
        }

        return exec.close();
    }
}

/// @title DenyAsset
/// @notice Admin command that blocks a list of assets via a virtual hook.
/// Each ASSET block in the input calls `denyAsset`. Only callable by the admin account.
abstract contract DenyAsset is AdminBase, DenyAssetHook {
    uint private immutable descriptor;

    constructor() {
        (, descriptor) = command("denyAsset", Specs.Empty, Specs.Asset, Specs.Empty, Flags.Admin);
    }

    /// @notice Deny each ASSET block in the admin input.
    /// @param context Admin command context carrying the ASSET input stream.
    /// @return Empty output state.
    /// @return Zero native budget credit.
    function denyAsset(
        bytes calldata context
    ) external returns (bytes memory, uint) {
        Execution memory exec = openAdminCommand(context, descriptor);

        while (exec.more()) {
            bytes32 asset = exec.unpackAsset();
            denyAsset(asset);
        }

        return exec.close();
    }
}
