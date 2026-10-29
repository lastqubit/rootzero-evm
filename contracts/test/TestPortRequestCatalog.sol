// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

import {Keys} from "../codec/Keys.sol";
import {Specs} from "../codec/Specs.sol";
import {Schemas} from "../codec/Schema.sol";

contract TestPortRequestCatalog {
    function catalog() external pure returns (bytes4, uint, string memory) {
        return (Keys.PortRequest, Specs.PortRequest, Schemas.PortRequest);
    }

    function accepts(uint size) external pure returns (bool) {
        return Specs.accepts(Specs.PortRequest, size);
    }
}
