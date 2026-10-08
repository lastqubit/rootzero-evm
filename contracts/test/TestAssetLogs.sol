// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

import {Encoder} from "../codec/Encoder.sol";
import {Logs} from "../codec/Logs.sol";
import {Specs} from "../codec/Specs.sol";
import {Schemas} from "../codec/Schema.sol";

contract TestAssetLogs {
    function catalog() external pure returns (uint, string memory) {
        return (Specs.AssetPreimage, Schemas.AssetPreimage);
    }

    function emitPreimage(bytes32 asset, bytes memory preimage) external returns (bytes memory) {
        bytes memory data = Encoder.createAssetPreimage(asset, preimage);
        Logs.metadata(uint(asset), data);
        return data;
    }

}
