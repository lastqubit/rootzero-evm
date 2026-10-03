// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;
import {Lanes} from "../codec/Lanes.sol";
import {Specs} from "../codec/Specs.sol";
contract TestLanes {
    function inspect(uint specification, uint codes) external pure returns (uint lane, uint spec, uint value, uint size) {
        lane = Lanes.create(specification, codes);
        spec = Lanes.spec(lane);
        value = Lanes.codes(lane);
        size = Specs.blockSize(spec);
    }
}
