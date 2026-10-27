// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

import {CommandHost, Host} from "../core/Host.sol";
import {UpstreamPort} from "../core/Upstream.sol";

error TestUpstreamFailed(bytes data);

contract TestUpstreamTarget is CommandHost {
    constructor(uint cmdr) CommandHost(cmdr, "TestUpstreamTarget") {}

    function portEcho(bytes calldata data) external payable returns (bytes memory, uint) {
        return (data, msg.value);
    }

    function portFail(bytes calldata data) external pure returns (bytes memory, uint) {
        revert TestUpstreamFailed(data);
    }
}

contract TestUpstreamCommandHost is CommandHost, UpstreamPort {
    constructor(uint cmdr, uint port) CommandHost(cmdr, "TestUpstreamCommandHost") UpstreamPort(port, "upstream") {}

    function callPaid(bytes calldata data, bool expectEmpty) external payable returns (bytes memory, uint) {
        return callUpstream(msg.value, data, expectEmpty);
    }

    function callFree(bytes calldata data, bool expectEmpty) external returns (bytes memory, uint) {
        return callUpstream(data, expectEmpty);
    }
}

contract TestUpstreamHost is Host, UpstreamPort {
    constructor(uint cmdr, uint port) Host(cmdr, "TestUpstreamHost", address(0)) UpstreamPort(port, "upstream") {}
}
