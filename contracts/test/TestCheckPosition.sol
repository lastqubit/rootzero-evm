// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;
import {Cursors} from "../utils/Cursors.sol";

import {ExecuteCheckPosition} from "../commands/Position.sol";
import {Runtime} from "../core/Runtime.sol";
import {AccessDenied} from "../core/Access.sol";
import {LegacyHeaders} from "./LegacyHeaders.sol";

contract TestCheckPosition is ExecuteCheckPosition {
    address private immutable tester = msg.sender;
    constructor() Runtime(0, address(0)) {}

    function enforceCaller(address caller) internal view override returns (address) {
        if (caller != tester) revert AccessDenied();
        return caller;
    }

    function commandId() external view returns (uint) { return checkPositionId(); }

    function schemaHeaders() external pure returns (uint64, uint64) {
        return (LegacyHeaders.Position, LegacyHeaders.PositionConstraints);
    }

    function checkMemory(bytes memory state, bytes calldata input, uint value)
        external pure returns (bool, bytes memory, uint)
    {
        (bool handled, bytes memory output, uint credit) = executeCheckPosition(bytes32(0), state, Cursors.wrap(input), value);
        bool same;
        assembly ("memory-safe") { same := eq(state, output) }
        assert(same);
        return (handled, output, credit);
    }

    function measureMemory(bytes memory state, bytes calldata input, uint value)
        external view returns (uint used, bool handled, bytes memory output, uint credit)
    {
        uint initial = gasleft();
        (handled, output, credit) = executeCheckPosition(bytes32(0), state, Cursors.wrap(input), value);
        used = initial - gasleft();
        bool same;
        assembly ("memory-safe") { same := eq(state, output) }
        assert(same);
    }
}
