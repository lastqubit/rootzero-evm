// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

import {Specs} from "../Codec.sol";
import {Execution, Executions} from "../execution/Execution.sol";
import {QueryBase} from "./Base.sol";

using Executions for Execution;

/// @notice Hook implemented by hosts that expose asset status queries.
abstract contract AssetStatusHook {
    /// @notice Resolve support status for one asset.
    /// Concrete implementations define the support policy and optional context codes.
    /// @param asset Requested asset identifier.
    /// @return status Asset support status. Zero means unsupported; nonzero means supported.
    function assetStatus(bytes32 asset) internal view virtual returns (uint status);
}

/// @title AssetStatus
/// @notice Rootzero query that checks support status for one or more assets.
/// The input is a run of `ASSET` blocks.
/// The response returns one `STATUS` form block per query entry, preserving input order.
abstract contract AssetStatus is QueryBase, AssetStatusHook {
    uint private immutable descriptor;

    constructor() {
        (, descriptor) = query("assetStatus", Specs.Asset, Specs.Status);
    }

    /// @notice Resolve asset support status for a run of requested assets.
    /// @param input Block-stream input consisting of `asset { bytes32 asset }` blocks.
    /// @return Block-stream response containing one `status { uint code }` form block per asset block.
    function assetStatus(bytes calldata input) external view returns (bytes memory) {
        Execution memory exec = openInput(input, descriptor);

        while (exec.more()) {
            bytes32 asset = exec.unpackAsset();
            uint status = assetStatus(asset);
            exec.outputStatus(status);
        }

        return close(exec);
    }
}
