// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;
import {Encoder, Logs, Keys, Specs, Sizes, Headers, Schemas} from "../Codec.sol";

contract TestEnvelopeLogs {
    function catalog() external pure returns (bytes4, uint, uint, uint, string memory) {
        return (Keys.Envelope, Specs.Envelope, Sizes.Envelope, Headers.Envelope, Schemas.Envelope);
    }

    function publish(uint portal, uint resources, bytes32 key, bytes32 digest, uint codes)
        external returns (bytes memory)
    {
        Logs.envelope(portal, resources, key, digest, codes);
        return Encoder.createEnvelope(portal, resources, key, digest);
    }
}
