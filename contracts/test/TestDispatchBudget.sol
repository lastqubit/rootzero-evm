// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;
import {Blocks} from "../codec/Blocks.sol";

import {DispatchPayablePort} from "../ports/Dispatch.sol";
import {Runtime} from "../core/Runtime.sol";
import {Execution, Executions} from "../execution/Execution.sol";
import {Nodes} from "../utils/Nodes.sol";
import {AccessDenied} from "../core/Access.sol";

/// @dev Dispatch fixture that consumes the resource value lane and transfers real ETH.
contract TestDispatchBudget is DispatchPayablePort {
    using Executions for Execution;

    address private immutable peer = msg.sender;
    event DispatchSpent(uint value, uint remaining);
    error TransferFailed();

    constructor() Runtime(0, address(0)) {}

    function enforcePeer(address caller) internal view override returns (address) {
        if (caller != peer) revert AccessDenied();
        return caller;
    }

    function dispatchTo(uint portal, uint resources, uint payloadCur, Execution memory funds) internal override {
        uint value = funds.useResourceValue(resources);
        (bool success, ) = Nodes.hostAddr(portal).call{value: value}(Blocks.toBytes(payloadCur));
        if (!success) revert TransferFailed();
        emit DispatchSpent(value, funds.budget);
    }
}
