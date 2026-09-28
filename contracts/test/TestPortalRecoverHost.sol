// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;
import {Cursors} from "../utils/Cursors.sol";

import {RecoverPayable} from "../commands/Recover.sol";
import {Host} from "../core/Host.sol";
import {ForwardHook, Portal} from "../core/Portal.sol";
import {Calls} from "../core/Calls.sol";
import {Execution, Executions} from "../execution/Execution.sol";

using Executions for Execution;

abstract contract TestTransport is ForwardHook {
    function receiveMessage(
        bytes32 key,
        uint messageCur,
        uint value
    ) internal returns (bytes32) {
        return forward(key, messageCur, value);
    }
}

contract TestPortalRecoverHost is Host, Portal, TestTransport, RecoverPayable {
    constructor(uint rootzero) Host(rootzero) {}

    function testForward(bytes32 key, bytes calldata message, uint value) external payable {
        receiveMessage(key, Cursors.wrap(message), value);
    }

    function testCallPortMemory(uint port, bytes calldata input, uint value) external payable returns (bytes memory, uint) {
        bytes memory data = input;
        (bytes4 selector, address target) = enforcePort(port);
        return Calls.raw(selector, target, value, data, true);
    }

    function getAdminAccount() external view returns (bytes32) {
        return admin;
    }

    function recover(
        uint handler,
        uint resources,
        bytes32 key,
        uint witnessCur,
        Execution memory funds
    ) internal override {
        uint resolvedCur = resolve(key, witnessCur);
        (bytes4 selector, address target) = enforcePort(handler);
        funds.rawCall(selector, target, uint128(resources), resolvedCur, true);
        emit Resolved(host, key);
    }
}
