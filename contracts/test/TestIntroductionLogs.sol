// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;
import {Encoder} from "../codec/Encoder.sol";
import {Logs} from "../codec/Logs.sol";
import {Specs, Sizes} from "../codec/Specs.sol";
import {Headers} from "../codec/Headers.sol";
import {Schemas} from "../codec/Schema.sol";

contract TestIntroductionLogs {
    function catalog() external pure returns (uint, uint, uint, string memory) {
        return (Specs.Introduction, Sizes.Introduction, Headers.Introduction, Schemas.Introduction);
    }

    function publish(uint peer, bytes32 origin, uint blocknum) external returns (bytes memory) {
        Logs.introduction(peer, origin, blocknum, "");
        return Encoder.createIntroduction(peer, origin, blocknum);
    }
}
