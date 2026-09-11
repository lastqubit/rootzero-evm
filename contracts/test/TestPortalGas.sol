// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

import {Portal} from "../core/Portal.sol";
import {Runtime} from "../core/Runtime.sol";

/// @dev Exhausts the child frame's gas through unaffordable memory expansion.
/// Unlike REVERT, this exceptional halt returns none of the forwarded gas.
contract TestOutOfGasPipe {
    function portPipePayable(bytes calldata) external payable returns (bytes memory, uint) {
        assembly ("memory-safe") {
            return(0, 0x100000000)
        }
    }
}

/// @dev Exercise production forwarding after a transport has allocated memory.
contract TestPortalGasReserve is Portal {
    constructor(uint cmdr) Runtime(cmdr) {}

    function testForward(bytes32 key, bytes calldata message, uint priorMemory)
        external payable returns (bytes32 miss)
    {
        // Exercise a transport that has already allocated memory before forwarding.
        bytes memory prior = new bytes(priorMemory);
        miss = forward(key, message, msg.value);
        // Keep the earlier allocation live without adding storage/event overhead.
        assembly ("memory-safe") { mstore(prior, 0) }
    }

    function getUnresolved(bytes32 key) external view returns (bytes32) {
        return unresolved[key];
    }
}

/// @dev Calls the production forward implementation without extra instrumentation.
contract TestPortalGas is Portal {
    constructor(uint cmdr) Runtime(cmdr) {}

    function testForward(bytes32 key, bytes calldata message) external payable returns (bytes32) {
        return forward(key, message, msg.value);
    }

    function getUnresolved(bytes32 key) external view returns (bytes32) {
        return unresolved[key];
    }
}

contract TestPortalGasExtraReserve is TestPortalGas {
    constructor(uint cmdr) TestPortalGas(cmdr) {
        gasReserve = 55_000;
    }
}
