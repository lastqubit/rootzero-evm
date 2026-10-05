// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

import {Encoder} from "../codec/Encoder.sol";
import {Logs} from "../codec/Logs.sol";
import {Codes} from "../utils/Codes.sol";
import {Specs, Sizes} from "../codec/Specs.sol";
import {Headers} from "../codec/Headers.sol";
import {Schemas} from "../codec/Schema.sol";

contract TestEndpointLogs {
    function catalog() external pure returns (uint, uint, uint, string memory) {
        return (Specs.Endpoint, Sizes.Endpoint, Headers.Endpoint, Schemas.Endpoint);
    }

    function publish(uint id, uint state, uint input, uint output) external returns (bytes memory) {
        Logs.endpoint(id, state, input, output, Codes.HostAdd);
        return Encoder.createEndpoint(id, state, input, output);
    }
}
