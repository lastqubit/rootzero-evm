// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

import {GuardBase} from "./Base.sol";
import {AssetAmount} from "../core/Types.sol";
import {Specs} from "../codec/Specs.sol";
import {Logs} from "../codec/Logs.sol";
import {Execution, Executions} from "../execution/Execution.sol";

using Executions for Execution;

/// @notice Hook implemented by hosts that update existing asset-pair pools.
abstract contract UpdatePoolHook {
    /// @notice Replace the virtual reserves of an existing pool with the supplied quantities.
    /// @dev Both ASSET_AMOUNT blocks are decoded before invocation. Hosts define pair
    /// ordering, enforce pool existence, and validate reserves and pricing policy.
    /// This action does not imply any transfer or change to actual account balances.
    /// @param a First pool asset and replacement reserve.
    /// @param b Second pool asset and replacement reserve.
    function updatePool(AssetAmount memory a, AssetAmount memory b) internal virtual;
}

/// @notice Opt-in guardian action for immediate updates of virtual pool reserves.
abstract contract UpdatePool is GuardBase, UpdatePoolHook {
    uint private immutable descriptor;
    uint private immutable id;

    constructor() {
        uint input = lane("#assetAmount[2] as (a, b)", "updatePool", Specs.AssetAmount);
        (id, descriptor) = guard("updatePool", input, Logs.Input);
    }

    /// @notice Update existing pools from consecutive ASSET_AMOUNT pairs.
    /// @dev Only active guardians may call, including for empty batches. An incomplete
    /// pair or hook failure reverts the entire batch. Logs INPUT after all hooks.
    /// @param input Raw ASSET_AMOUNT pairs; amounts replace reserves rather than add deltas.
    function updatePool(bytes calldata input) external onlyGuardian {
        runGuard(id, descriptor, input, updatePoolOne);
    }

    function updatePoolOne(Execution memory exec) private {
        AssetAmount memory a = exec.unpackAssetAmountValue();
        AssetAmount memory b = exec.unpackAssetAmountValue();
        updatePool(a, b);
    }
}
