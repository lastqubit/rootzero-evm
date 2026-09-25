// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

import {ExecuteCheckBalance} from "../commands/Balance.sol";
import {ExecuteBootstrap} from "../commands/Bootstrap.sol";
import {Runtime} from "../core/Runtime.sol";

contract TestAdapterOptimizations is ExecuteCheckBalance, ExecuteBootstrap {
    mapping(bytes32 => uint) public balances;

    constructor() Runtime(0) {}

    function enforceCaller(address caller) internal pure override returns (address) { return caller; }

    function nativeAsset() external view returns (bytes32) { return chainAsset; }
    function seed(bytes32 asset, uint amount) external { balances[asset] = amount; }

    function debitAccount(bytes32, bytes32 asset, uint amount) internal override {
        balances[asset] -= amount;
    }

    function measureBalance(bytes memory state, bytes calldata input, uint value)
        external view returns (uint used, bool handled, bytes memory output, uint credit)
    {
        uint initial = gasleft();
        (handled, output, credit) = executeCheckBalance(bytes32(0), state, input, value);
        used = initial - gasleft();
        bool same;
        assembly ("memory-safe") { same := eq(state, output) }
        assert(same);
    }

    function measureBootstrap(bytes memory state, bytes calldata input, uint value)
        external returns (uint used, bool handled, bytes memory output, uint credit)
    {
        uint initial = gasleft();
        (handled, output, credit) = executeBootstrap(bytes32(0), state, input, value);
        used = initial - gasleft();
    }

    function measureBoth(bytes calldata input, bytes calldata limits, uint value)
        external returns (uint used, bool handled, bytes memory output, uint credit)
    {
        bytes memory empty = new bytes(0);
        uint initial = gasleft();
        (, bytes memory state, uint budget) = executeBootstrap(bytes32(0), empty, input, value);
        (handled, output, credit) = executeCheckBalance(bytes32(0), state, limits, budget);
        used = initial - gasleft();
        bool same;
        assembly ("memory-safe") { same := eq(state, output) }
        assert(same);
    }
}
