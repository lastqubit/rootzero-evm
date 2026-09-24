// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

import {ExecuteCheckBalance} from "../commands/Balance.sol";
import {ExecuteCheckPosition} from "../commands/Position.sol";
import {Runtime} from "../core/Runtime.sol";
import {AccessDenied} from "../core/Access.sol";
import {Headers} from "../codec/Specs.sol";

contract TestCheckBalance is ExecuteCheckBalance, ExecuteCheckPosition {
    address private immutable tester = msg.sender;
    constructor() Runtime(0) {}

    function enforceCaller(address caller) internal view override returns (address) {
        if (caller != tester) revert AccessDenied();
        return caller;
    }

    function commandId() external view returns (uint) { return checkBalanceId(); }

    function schemaHeaders() external pure returns (uint64, uint64) {
        return (Headers.Balance, Headers.AssetLimits);
    }

    function checkMemory(bytes memory state, bytes calldata input, uint value)
        external pure returns (bool, bytes memory, uint)
    {
        (bool handled, bytes memory output, uint credit) = executeCheckBalance(bytes32(0), state, input, value);
        bool same;
        assembly ("memory-safe") { same := eq(state, output) }
        assert(same);
        return (handled, output, credit);
    }
}
