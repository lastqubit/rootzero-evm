// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

import { AssetStatus } from "../queries/Asset.sol";
import {Runtime} from "../core/Runtime.sol";

contract TestAssetStatusQuery is AssetStatus {
    bytes32 public immutable allowedAssetId = bytes32(uint(0xA11));

    constructor() Runtime(0) {}

    function assetStatus(bytes32 asset) internal view override returns (uint status) {
        return asset == allowedAssetId ? 1 : 0;
    }
}
