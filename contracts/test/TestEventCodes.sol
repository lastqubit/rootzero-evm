// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

import {ActivityEvent} from "../events/Activity.sol";
import {NodeEvent} from "../events/Node.sol";
import {GuardianEvent} from "../events/Guardian.sol";
import {Entities, Codes} from "../Events.sol";
import {Entities as UtilityEntities} from "../Utils.sol";

contract TestEventCodes is ActivityEvent, NodeEvent, GuardianEvent {
    function entityKinds() external pure returns (uint[11] memory) {
        return [Entities.Asset, Entities.Account, Entities.Host, Entities.Command,
            Entities.Query, Entities.Route, Entities.Position, Entities.Guardian, UtilityEntities.Pool,
            Entities.Port, UtilityEntities.Balance];
    }

    function emitAddRoute(bytes32 account, bytes32 route) external {
        emit Activity(account, route, 0, Codes.AddRouteThenActive);
    }

    function emitRemoveRoute(bytes32 account, bytes32 route) external {
        emit Activity(account, route, 0, Codes.RemoveRouteThenInactive);
    }

    function emitAllowAsset(bytes32 account, bytes32 asset) external {
        emit Activity(account, asset, 0, Codes.AllowAssetThenActive);
    }

    function emitDenyAsset(bytes32 account, bytes32 asset) external {
        emit Activity(account, asset, 0, Codes.DenyAssetThenInactive);
    }

    function emitActivity(bytes32 account, bytes32 subject, uint value, uint codes) external {
        emit Activity(account, subject, value, codes);
    }
    function emitNode(uint host, uint node, uint codes) external {
        emit Node(host, node, codes);
    }
    function emitGuardian(uint host, bytes32 account, uint codes) external {
        emit Guardian(host, account, codes);
    }
}
