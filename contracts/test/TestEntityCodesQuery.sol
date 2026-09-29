// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

import {GetEntityCodes, GetEntityCodesHook, GetAssetCodes} from "../Endpoints.sol";
import {States} from "../utils/States.sol";
import {Runtime} from "../core/Runtime.sol";

contract TestEntityCodesQuery is GetEntityCodes, GetAssetCodes {
    constructor() Runtime(0) {}

    function entityCodes(uint entity) internal pure override returns (uint codes) {
        if (entity == 1) return States.Active;
        if (entity == 2) return States.Inactive;
        // Test-only condition illustrates a host-defined condition without Active/Inactive.
        if (entity == type(uint).max) return 0xa0000010;
        return 0;
    }

    function assetCodes(bytes32) internal pure override returns (uint codes) {
        return States.Inactive;
    }
}
