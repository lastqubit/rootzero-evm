// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;
import {Logs} from "../../codec/Logs.sol";

import {AdminBase, Execution, Executions, Flags, Specs} from "./Base.sol";
import {AssetAmount} from "../../core/Types.sol";

using Executions for Execution;

/// @notice Hook implemented by hosts that add asset-pair pools.
abstract contract AddPoolHook {
    /// @notice Add a pool with two asset quantities.
    /// @dev Both ASSET_AMOUNT blocks are decoded before invocation. Implementations define
    /// pair ordering, validate assets and quantities, and handle existing pools and funding.
    /// @param a First pool asset and quantity.
    /// @param b Second pool asset and quantity.
    function addPool(AssetAmount memory a, AssetAmount memory b) internal virtual;
}

/// @notice Hook implemented by hosts that remove asset-pair pools.
abstract contract RemovePoolHook {
    /// @notice Remove the pool identified by two assets.
    /// @dev Both ASSET blocks are decoded before invocation. Implementations define
    /// pair ordering and removal requirements, including outstanding liquidity or obligations.
    /// @param a First pool asset.
    /// @param b Second pool asset.
    function removePool(bytes32 a, bytes32 b) internal virtual;
}

/// @notice Admin command that adds one pool per pair of ASSET_AMOUNT inputs.
abstract contract AddPool is AdminBase, AddPoolHook {
    uint private immutable descriptor;
    uint private immutable id;

    constructor() {
        uint input = lane("#assetAmount[2] as (a, b)", "addPool", Specs.AssetAmount);
        (id, descriptor) = command("addPool", Specs.Empty, input, Specs.Empty, Logs.Input | Flags.Admin);
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
        AssetAmount memory a = exec.unpackAssetAmountValue();
        AssetAmount memory b = exec.unpackAssetAmountValue();
        addPool(a, b);
    }
}

/// @notice Admin command that removes one pool per pair of ASSET inputs.
abstract contract RemovePool is AdminBase, RemovePoolHook {
    uint private immutable descriptor;
    uint private immutable id;

    constructor() {
        uint input = lane("#asset[2] as (a, b)", "removePool", Specs.Asset);
        (id, descriptor) = command("removePool", Specs.Empty, input, Specs.Empty, Logs.Input | Flags.Admin);
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
        bytes32 a = exec.unpackAsset();
        bytes32 b = exec.unpackAsset();
        removePool(a, b);
    }
}
