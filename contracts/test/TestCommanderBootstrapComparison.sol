// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

import {PreviousInputBootstrap} from "./PreviousInputBootstrap.sol";
import {ExecuteBootstrap} from "../commands/Bootstrap.sol";
import {Balances} from "../core/Balances.sol";
import {Runtime, ChainAsset} from "../core/Runtime.sol";
import {Cursors, Execute, Keys} from "../Codec.sol";
import {UnexpectedState, InvalidBlock, ValueOverflow} from "../utils/Errors.sol";

abstract contract CommanderBootstrapLedger is Balances {
    function seed(bytes32 account, bytes32[] calldata assets, uint amount) external {
        for (uint i; i < assets.length; ++i) balances[account][assets[i]] = amount;
    }
    function balanceOf(bytes32 account, bytes32 asset) external view returns (uint) {
        return balances[account][asset];
    }
}

/// @dev Actual production adapter, with Main's ledger hook after event migration.
contract CommanderCurrentBootstrap is ExecuteBootstrap, CommanderBootstrapLedger {
    constructor() Runtime(0) {}
    function enforceCaller(address caller) internal pure override returns (address) { return caller; }
    function nativeAsset() external view returns (bytes32) { return chainAsset; }
    function debitAccount(bytes32 account, bytes32 asset, uint amount) internal override {
        if (amount != 0) debitFrom(account, asset, amount);
    }
    function measure(bytes32 account, bytes calldata input, uint value)
        external returns (uint gasUsed, bytes memory output, uint remaining)
    {
        bytes memory empty;
        uint cur = Cursors.wrap(input);
        uint start = gasleft();
        (, output, remaining) = executeBootstrap(account, empty, cur, value);
        gasUsed = start - gasleft();
    }
}

/// @dev Frozen input-logging adapter, with the same ledger hook.
contract CommanderInputBootstrap is PreviousInputBootstrap, CommanderBootstrapLedger {
    constructor() Runtime(0) {}
    function enforceCaller(address caller) internal pure override returns (address) { return caller; }
    function nativeAsset() external view returns (bytes32) { return chainAsset; }
    function debitAccount(bytes32 account, bytes32 asset, uint amount) internal override {
        if (amount != 0) debitFrom(account, asset, amount);
    }
    function measure(bytes32 account, bytes calldata input, uint value)
        external returns (uint gasUsed, bytes memory output, uint remaining)
    {
        bytes memory empty;
        uint cur = Cursors.wrap(input);
        uint start = gasleft();
        (, output, remaining) = executeBootstrap(account, empty, cur, value);
        gasUsed = start - gasleft();
    }
}

/// @dev Frozen 1.48.0 Bootstrap algorithm installed in Commander on 2026-10-05.
/// Retains the fixed 104-byte decoder, original allocation without a leading
/// log word, and Main's Balance-emitting debit hook. BALANCE writing is unchanged.
contract CommanderHistoricalBootstrap is CommanderBootstrapLedger, ChainAsset {
    uint private constant BootstrapHeader = (uint(uint32(Keys.Bootstrap)) << 32) | 96;
    event Balance(bytes32 indexed account, bytes32 asset, uint balance);

    function allocateLegacyBalances(uint count) private pure returns (uint abs, bytes memory output) {
        uint size;
        unchecked { size = count * 72; }
        if (size > type(uint32).max) revert ValueOverflow();
        assembly ("memory-safe") {
            output := mload(0x40)
            abs := add(output, 32)
            mstore(output, size)
            mstore(add(abs, size), 0)
            mstore(0x40, add(abs, and(add(size, 31), not(31))))
        }
    }
    function unpackLegacyBootstrap(uint abs) private pure returns (bytes32 asset, uint amount, uint budget) {
        uint header;
        assembly ("memory-safe") {
            header := shr(192, calldataload(abs))
            asset := calldataload(add(abs, 8))
            amount := calldataload(add(abs, 40))
            budget := calldataload(add(abs, 72))
        }
        if (header != BootstrapHeader) revert InvalidBlock();
    }
    function debitAccount(bytes32 account, bytes32 asset, uint amount) private {
        if (amount == 0) return;
        uint balance = debitFrom(account, asset, amount);
        emit Balance(account, asset, balance);
    }
    function bootstrap(bytes32 account, bytes32 asset, uint amount, uint budget, uint value) private returns (uint) {
        if (asset == chainAsset) {
            uint funded = amount < value ? amount : value;
            unchecked { amount -= funded; value -= funded; }
            amount += budget;
        } else {
            if (amount != 0) debitAccount(account, asset, amount);
            amount = budget;
        }
        if (amount != 0) debitAccount(account, chainAsset, amount);
        return value + budget;
    }
    function executeLegacyBootstrap(bytes32 account, bytes memory state, uint cur, uint value)
        private returns (bool, bytes memory output, uint remaining)
    {
        if (state.length != 0) revert UnexpectedState();
        (uint abs, uint end) = Execute.bounds(cur, 104);
        uint i;
        unchecked { (i, output) = allocateLegacyBalances((end - abs) / 104); }
        remaining = value;
        while (abs < end) {
            (bytes32 asset, uint amount, uint budget) = unpackLegacyBootstrap(abs);
            remaining = bootstrap(account, asset, amount, budget, remaining);
            i = Execute.writeBalance(i, asset, amount);
            unchecked { abs += 104; }
        }
        return (true, output, remaining);
    }
    function measure(bytes32 account, bytes calldata input, uint value)
        external returns (uint gasUsed, bytes memory output, uint remaining)
    {
        bytes memory empty;
        uint cur = Cursors.wrap(input);
        uint start = gasleft();
        (, output, remaining) = executeLegacyBootstrap(account, empty, cur, value);
        gasUsed = start - gasleft();
    }
}
