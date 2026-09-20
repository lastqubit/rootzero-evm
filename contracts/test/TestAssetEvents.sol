// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

import {AssetEvent, AssetPreimageEvent} from "../Events.sol";

contract TestAssetEvents is AssetEvent, AssetPreimageEvent {
    function emitPreimage(bytes32 asset, bytes calldata preimage) external {
        emit AssetPreimage(asset, preimage);
    }

    function emitAsset(uint host, bytes32 asset, uint32 action, uint status) external {
        emit Asset(host, asset, action, status);
    }
}
