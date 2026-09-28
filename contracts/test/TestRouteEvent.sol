// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

import {RouteEvent} from "../Events.sol";

contract TestRouteEvent is RouteEvent {
    function emitRoute(uint host, uint portal, uint codes) external {
        emit Route(host, portal, codes);
    }
}
