// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;
import {Encoder, Logs, Keys, Specs, Sizes, Headers, Schemas} from "../Codec.sol";

contract TestResolutionLogs {
    function catalog() external pure returns (bytes4, uint, uint, uint, string memory) {
        return (Keys.Resolution, Specs.Resolution, Sizes.Resolution, Headers.Resolution, Schemas.Resolution);
    }
    function publish(bytes32 key, bytes32 digest, uint codes) external returns (bytes memory) {
        Logs.resolution(key, digest, codes);
        return Encoder.createResolution(key, digest);
    }
}
