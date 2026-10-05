// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

import {Encoder} from "../codec/Encoder.sol";
import {Logs} from "../codec/Logs.sol";
import {Codes} from "../utils/Codes.sol";
import {Specs} from "../codec/Specs.sol";
import {Schemas} from "../codec/Schema.sol";

contract TestAssetLogs {
    function catalog() external pure returns (uint, string memory) {
        return (Specs.AssetPreimage, Schemas.AssetPreimage);
    }

    function emitPreimage(bytes32 asset, bytes memory preimage) external returns (bytes memory) {
        bytes memory data = Encoder.createAssetPreimage(asset, preimage);
        Logs.mem(Codes.AssetAnnotate, Encoder.pos(data, 0), data.length);
        return data;
    }

    function emitAsset(bytes32 asset, uint codes) external {
        bytes memory data = Encoder.createAsset(asset);
        Logs.mem(codes, Encoder.pos(data, 0), data.length);
    }

    function emitHostAsset(uint host, bytes32 asset, uint codes) external {
        bytes memory data = Encoder.createHostAsset(host, asset);
        Logs.mem(codes, Encoder.pos(data, 0), data.length);
    }
}
