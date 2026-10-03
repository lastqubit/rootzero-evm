// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

import {Specs} from "../Codec.sol";
import {Execution, Executions} from "../execution/Execution.sol";
import {QueryBase} from "./Base.sol";

using Executions for Execution;

/// @notice Hook implemented by hosts that expose current asset conditions.
abstract contract GetAssetCodesHook {
    /// @notice Resolve current state codes for one asset.
    /// @dev Must return exactly one States.Active or States.Inactive code.
    /// Zero is not inactive. Additional applicable condition codes may accompany it;
    /// do not return historical actions or effects. Implementations own the policy
    /// and packing validation; the query encodes the returned word unchanged.
    /// @param asset Requested asset identifier.
    /// @return codes Packed identifiers describing the asset's current condition.
    function assetCodes(bytes32 asset) internal view virtual returns (uint codes);
}

/// @title GetAssetCodes
/// @notice Query current asset conditions for one or more assets.
/// Input is a run of ASSET blocks; output is one CODES block per asset in input order.
abstract contract GetAssetCodes is QueryBase, GetAssetCodesHook {
    uint private immutable descriptor;

    constructor() {
        (, descriptor) = query("assetCodes", Specs.Asset, Specs.Codes);
    }

    /// @notice Resolve current conditions for a run of requested assets.
    /// @param input Block stream of asset { bytes32 asset } entries.
    /// @return One codes { uint codes } block for each input entry, in the same order.
    function assetCodes(bytes calldata input) external view returns (bytes memory) {
        return runQuery(descriptor, input, assetCodesOne);
    }

    function assetCodesOne(Execution memory exec) private view {
        bytes32 asset = exec.unpackAsset();
        exec.outputCodes(assetCodes(asset));
    }
}
