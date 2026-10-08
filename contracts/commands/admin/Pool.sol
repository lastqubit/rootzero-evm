// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;
import {Logs} from "../../codec/Logs.sol";

import {AdminBase, Execution, Executions, Flags, Specs} from "./Base.sol";
import {GroupsAnnot} from "../../annotations/Groups.sol";
import {AssetAmount} from "../../core/Types.sol";

using Executions for Execution;

/// @notice Hook implemented by hosts that add asset-pair pools.
abstract contract AddPoolHook {
    /// @notice Add a pool with two asset quantities.
    /// @dev Both ASSET_AMOUNT blocks are decoded before invocation. Implementations define
    /// pair ordering, validate assets and quantities, and handle existing pools and funding.
    /// @param first First pool asset and quantity.
    /// @param second Second pool asset and quantity.
    function addPool(AssetAmount memory first, AssetAmount memory second) internal virtual;
}

/// @notice Hook implemented by hosts that remove asset-pair pools.
abstract contract RemovePoolHook {
    /// @notice Remove the pool identified by two assets.
    /// @dev Both ASSET blocks are decoded before invocation. Implementations define
    /// pair ordering and removal requirements, including outstanding liquidity or obligations.
    /// @param first First pool asset.
    /// @param second Second pool asset.
    function removePool(bytes32 first, bytes32 second) internal virtual;
}

/// @notice Admin command that adds one pool per pair of ASSET_AMOUNT inputs.
abstract contract AddPool is AdminBase, AddPoolHook, GroupsAnnot {
    uint private immutable descriptor;
    uint private immutable id;

    constructor() {
        (id, descriptor) = command("addPool", Specs.Empty, Specs.AssetAmount, Specs.Empty, Logs.Input | Flags.Admin);
        annotateGroups(id, "#input as (first, second)");
    }

    /// @notice Add pools from consecutive ASSET_AMOUNT pairs.
    /// @dev Empty batches are accepted. An incomplete pair or hook failure reverts the entire batch.
    /// @dev Logs the complete host-scoped INPUT batch after hooks.
    /// @param context Admin context containing the ASSET_AMOUNT input pairs.
    /// @return Empty output state.
    /// @return Zero native budget credit.
    function addPool(bytes calldata context) external returns (bytes memory, uint) {
        return runAdmin(id, descriptor, context, addPoolOne);
    }

    function addPoolOne(Execution memory exec) private {
        AssetAmount memory first = exec.unpackAssetAmountValue();
        AssetAmount memory second = exec.unpackAssetAmountValue();
        addPool(first, second);
    }
}

/// @notice Admin command that removes one pool per pair of ASSET inputs.
abstract contract RemovePool is AdminBase, RemovePoolHook, GroupsAnnot {
    uint private immutable descriptor;
    uint private immutable id;

    constructor() {
        (id, descriptor) = command("removePool", Specs.Empty, Specs.Asset, Specs.Empty, Logs.Input | Flags.Admin);
        annotateGroups(id, "#input as (first, second)");
    }

    /// @notice Remove pools from consecutive ASSET pairs.
    /// @dev Empty batches are accepted. An incomplete pair or hook failure reverts the entire batch.
    /// @dev Logs the complete host-scoped INPUT batch after hooks.
    /// @param context Admin context containing the ASSET input pairs.
    /// @return Empty output state.
    /// @return Zero native budget credit.
    function removePool(bytes calldata context) external returns (bytes memory, uint) {
        return runAdmin(id, descriptor, context, removePoolOne);
    }

    function removePoolOne(Execution memory exec) private {
        bytes32 first = exec.unpackAsset();
        bytes32 second = exec.unpackAsset();
        removePool(first, second);
    }
}
