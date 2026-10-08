// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;
import {Logs} from "../codec/Logs.sol";
contract TestEventCategories {
    function emitScalars(bytes32 subject, uint value, bytes memory live) external {
        string memory emptyName;
        bytes32 beforeHash = keccak256(live);
        uint beforeFree;
        assembly ("memory-safe") {
            beforeFree := mload(0x40)
            mstore(beforeFree, not(0))
            mstore(add(beforeFree, 32), not(0))
        }
        Logs.access(value, false);
        Logs.access(value, true);
        Logs.endpoint(value, value, value, value, emptyName);
        Logs.balance(subject, subject, value);
        Logs.introduction(value, subject, value, emptyName);
        Logs.envelope(value, value, subject, subject);
        Logs.resolution(subject, subject, false);
        Logs.resolution(subject, subject, true);
        uint afterFree;
        uint zero;
        assembly ("memory-safe") { afterFree := mload(0x40) zero := mload(0x60) }
        require(beforeFree == afterFree && zero == 0 && beforeHash == keccak256(live));
    }
    function publish(uint subject, bytes memory data, bool sharedEmpty) external returns (bytes memory value) {
        if (!sharedEmpty) value = data;
        bytes32 beforeHash = keccak256(value);
        uint beforeFree;
        assembly ("memory-safe") { beforeFree := mload(0x40) mstore(beforeFree, not(0)) }
        Logs.metadata(subject, value);
        Logs.metadata(subject, value);
        uint afterFree;
        uint zero;
        assembly ("memory-safe") { afterFree := mload(0x40) zero := mload(0x60) }
        require(beforeFree == afterFree && zero == 0 && beforeHash == keccak256(value));
    }
}
