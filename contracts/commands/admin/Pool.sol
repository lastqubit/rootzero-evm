// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;
import {Logs} from "../../codec/Logs.sol";

import {AdminBase, Execution, Executions, Flags, Specs} from "./Base.sol";
import {AssetAmount} from "../../core/Types.sol";

using Executions for Execution;

/// @title AddPoolHook
/// @notice Hook implemented by hosts that add asset-pair pools.
abstract contract AddPoolHook {
    /// @notice Add a pool with two asset quantities.
    /// @dev Both ASSET_AMOUNT blocks are decoded before invocation. Implementations define
    /// pair ordering, validate assets and quantities, and handle existing pools and funding.
    /// @param a First pool asset and quantity.
    /// @param b Second pool asset and quantity.
    function addPool(AssetAmount memory a, AssetAmount memory b) internal virtual;
}

/// @title RemovePoolHook
/// @notice Hook implemented by hosts that remove asset-pair pools.
abstract contract RemovePoolHook {
    /// @notice Remove the pool identified by two assets.
    /// @dev Both ASSET blocks are decoded before invocation. Implementations define
    /// pair ordering and removal requirements, including outstanding liquidity or obligations.
    /// @param a First pool asset.
    /// @param b Second pool asset.
    function removePool(bytes32 a, bytes32 b) internal virtual;
}

/// @title AddPool
/// @notice Admin command that adds one pool per pair of ASSET_AMOUNT inputs.
abstract contract AddPool is AdminBase, AddPoolHook {
    uint private immutable descriptor;

    constructor() {
        (, descriptor) = command("addPool", Specs.Empty, addPoolInput(), Specs.Empty, Logs.Input | Flags.Admin);
    }

    /// @notice Input lane for `addPool`: pairs of asset amounts, one pair per pool.
    /// @dev Called once from the constructor and publishes the `addPool` lane description.
    /// An override that replaces the description returns its own `lane(...)` without
    /// calling `super`; one that only adds a variant wraps `super.addPoolInput()`.
    /// The lane must keep the ASSET_AMOUNT block spec.
    /// @return Packed ASSET_AMOUNT input lane with the `addPool` lane key.
    function addPoolInput() internal virtual returns (uint) {
        return lane("#assetAmount[2] as (a, b)", "addPool", Specs.AssetAmount);
    }

    /// @notice Add pools from consecutive ASSET_AMOUNT pairs.
    /// @dev Empty batches are accepted. An incomplete pair or hook failure reverts the entire batch.
    /// @dev Hints callers to record the complete host-scoped INPUT batch.
    /// @param context Admin context containing the ASSET_AMOUNT input pairs.
    /// @return Empty output state.
    /// @return Zero native budget credit.
    function addPool(bytes calldata context) external returns (bytes memory, uint) {
        return runAdmin(descriptor, context, addPoolOne);
    }

    /// @dev Process one ASSET_AMOUNT / ASSET_AMOUNT item for the AddPool endpoint.
    /// @param exec Execution containing the account, source cursors, output writer, and native-value budget.
    function addPoolOne(Execution memory exec) private {
        AssetAmount memory a = exec.unpackAssetAmountValue();
        AssetAmount memory b = exec.unpackAssetAmountValue();
        addPool(a, b);
    }
}

/// @title RemovePool
/// @notice Admin command that removes one pool per pair of ASSET inputs.
abstract contract RemovePool is AdminBase, RemovePoolHook {
    uint private immutable descriptor;

    constructor() {
        (, descriptor) = command("removePool", Specs.Empty, removePoolInput(), Specs.Empty, Logs.Input | Flags.Admin);
    }

    /// @notice Input lane for `removePool`: pairs of assets, one pair per pool.
    /// @dev Called once from the constructor and publishes the `removePool` lane description.
    /// An override that replaces the description returns its own `lane(...)` without
    /// calling `super`; one that only adds a variant wraps `super.removePoolInput()`.
    /// The lane must keep the ASSET block spec.
    /// @return Packed ASSET input lane with the `removePool` lane key.
    function removePoolInput() internal virtual returns (uint) {
        return lane("#asset[2] as (a, b)", "removePool", Specs.Asset);
    }

    /// @notice Remove pools from consecutive ASSET pairs.
    /// @dev Empty batches are accepted. An incomplete pair or hook failure reverts the entire batch.
    /// @dev Hints callers to record the complete host-scoped INPUT batch.
    /// @param context Admin context containing the ASSET input pairs.
    /// @return Empty output state.
    /// @return Zero native budget credit.
    function removePool(bytes calldata context) external returns (bytes memory, uint) {
        return runAdmin(descriptor, context, removePoolOne);
    }

    /// @dev Process one ASSET / ASSET item for the RemovePool endpoint.
    /// @param exec Execution containing the account, source cursors, output writer, and native-value budget.
    function removePoolOne(Execution memory exec) private {
        bytes32 a = exec.unpackAsset();
        bytes32 b = exec.unpackAsset();
        removePool(a, b);
    }
}
