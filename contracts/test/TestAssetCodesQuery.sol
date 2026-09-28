// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

import {AssetCodes, AssetCodesHook} from "../Endpoints.sol";
import {States} from "../utils/States.sol";
import {Runtime} from "../core/Runtime.sol";

contract TestAssetCodesQuery is AssetCodes {
    bytes32 public immutable allowedAssetId = bytes32(uint(0xA11));

    constructor() Runtime(0) {}

    function assetCodes(bytes32 asset) internal view override returns (uint codes) {
        return asset == allowedAssetId ? States.Active : States.Inactive;
    }
}
