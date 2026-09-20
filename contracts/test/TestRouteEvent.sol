// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

import {RouteEvent} from "../Events.sol";

contract TestRouteEvent is RouteEvent {
    function emitRoute(uint host, uint portal, uint32 action, uint status) external {
        emit Route(host, portal, action, status);
    }
}
