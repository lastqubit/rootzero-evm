// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

import {Entities, Codes} from "../Utils.sol";
import {Entities as UtilityEntities} from "../Utils.sol";

contract TestCodeCatalog {
    function entityKinds() external pure returns (uint[11] memory) {
        return [Entities.Asset, Entities.Account, Entities.Host, Entities.Command,
            Entities.Query, Entities.Route, Entities.Position, Entities.Guardian, UtilityEntities.Pool,
            Entities.Port, UtilityEntities.Balance];
    }

    function routeAndAssetCodes() external pure returns (uint[4] memory) {
        return [Codes.AddRouteThenActive, Codes.RemoveRouteThenInactive,
            Codes.AllowAssetThenActive, Codes.DenyAssetThenInactive];
    }
}
