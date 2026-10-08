// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

import {Host} from "../core/Host.sol";
import {Logs} from "../codec/Logs.sol";
import {PreviousNamingEncoder} from "./PreviousNaming.sol";

contract TestNamedHost is Host {
    constructor(uint commander, string memory name) Host(commander, name) {}

    function announce(uint target, string memory name) external {
        introduceTo(target, name);
    }
}

contract TestNamedDiscovery {
    function publish(uint id, bytes32 account, string memory name, bool sharedEmpty)
        external returns (string memory value)
    {
        if (!sharedEmpty) value = name;
        bytes32 beforeHash = keccak256(bytes(value));
        uint beforeFree;
        assembly ("memory-safe") { beforeFree := mload(0x40) }
        Logs.endpoint(id, 1, 2, 3, value);
        Logs.introduction(id, account, 4, value);
        uint afterFree;
        uint zero;
        assembly ("memory-safe") { afterFree := mload(0x40) zero := mload(0x60) }
        require(beforeFree == afterFree && zero == 0 && beforeHash == keccak256(bytes(value)));
    }

    function registration(bool previous, string memory name) external returns (uint used) {
        uint start = gasleft();
        if (previous) {
            // Frozen pre-name Endpoint header followed by its separate LABEL metadata.
            assembly ("memory-safe") {
                let pos := mload(0x40)
                mstore8(pos, 5)
                mstore(add(pos, 1), 11)
                mstore(add(pos, 33), 1)
                mstore(add(pos, 65), 2)
                mstore(add(pos, 97), 3)
                log0(pos, 129)
            }
            Logs.metadata(11, PreviousNamingEncoder.createLabel(bytes32(0), bytes(name)));
        } else {
            Logs.endpoint(11, 1, 2, 3, name);
        }
        used = start - gasleft();
    }
}
