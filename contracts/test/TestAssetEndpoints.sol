// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

import {Host} from "../Core.sol";
import {AllowAsset, DenyAsset, AllowAssetPort, DenyAssetPort} from "../Endpoints.sol";

contract TestAssetEndpoints is Host, AllowAsset, DenyAsset, AllowAssetPort, DenyAssetPort {
    mapping(bytes32 => bool) public allowed;

    constructor(uint commander, uint peer) Host(commander) { authorizeNode(peer); }

    function allowAsset(bytes32 asset) internal override { allowed[asset] = true; }
    function denyAsset(bytes32 asset) internal override { allowed[asset] = false; }
}
