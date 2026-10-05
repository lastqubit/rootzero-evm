// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

import {Balances} from "../core/Balances.sol";
import {ChainAsset} from "../core/Runtime.sol";
import {Blocks, Cursors, Execute, Keys, Logs} from "../Codec.sol";
import {Codes, Entities} from "../Utils.sol";

/// @dev Logging-only comparison: identical ledger, decoding, allocation and current
/// Bootstrap funding for all variants. This is not a replacement Commander or a
/// benchmark of its access checks, external transfers, dispatch or old Bootstrap codec.
abstract contract CommanderLogComparison is Balances, ChainAsset {
    uint internal constant Credit = 0;
    uint internal constant Debit = 1;
    uint internal constant Bootstrap = 2;
    uint internal constant Cashin = 3;
    uint internal constant Root = 4;
    uint internal constant RoundTrip = 5;
    uint internal constant Endpoint = uint(0x03020300) << 224;

    function nativeAsset() external view returns (bytes32) { return chainAsset; }
    function seed(bytes32 account, bytes32[] calldata assets, uint amount) external {
        for (uint i; i < assets.length; ++i) balances[account][assets[i]] = amount;
    }
    function balanceOf(bytes32 account, bytes32 asset) external view returns (uint) {
        return balances[account][asset];
    }

    function changed(bytes32 account, bytes32 asset, uint balance) internal virtual;
    function stream(uint operation, bytes memory data, uint cur) internal virtual;
    function nativeDebit(uint amount) internal virtual;
    function cashedIn(bytes32 account, uint amount) internal virtual;
    function rooted(bytes32 account, uint value, bool before) internal virtual;

    function debit(bytes32 account, bytes32 asset, uint amount) private {
        if (amount == 0) return;
        changed(account, asset, debitFrom(account, asset, amount));
    }
    function credit(bytes32 account, bytes32 asset, uint amount) private {
        if (amount == 0) return;
        changed(account, asset, creditTo(account, asset, amount));
    }
    function creditState(bytes32 account, bytes memory state) private {
        stream(Credit, state, 0);
        (uint abs, uint end) = Execute.bounds(state, 72);
        while (abs < end) {
            (bytes32 asset, uint amount) = Execute.unpackBalanceMemory(abs);
            credit(account, asset, amount);
            unchecked { abs += 72; }
        }
    }
    function debitInput(bytes32 account, uint cur) private returns (bytes memory output) {
        (uint abs, uint end) = Execute.bounds(cur, 72);
        uint i;
        (i, output) = Execute.allocateBalances((end - abs) / 72);
        while (abs < end) {
            (bytes32 asset, uint amount) = Execute.unpackAssetAmount(abs);
            debit(account, asset, amount);
            i = Execute.writeBalance(i, asset, amount);
            unchecked { abs += 72; }
        }
        stream(Debit, output, 0);
    }
    function bootstrap(bytes32 account, uint cur, uint value) private returns (bytes memory output, uint remaining) {
        (uint budget, uint amountsCur) = Blocks.unpackBootstrapExact(cur);
        (uint abs, uint end) = Execute.bounds(amountsCur, 72);
        uint i;
        (i, output) = Execute.allocateBalances((end - abs) / 72);
        bytes memory empty;
        stream(Bootstrap, empty, cur);
        uint nativeAmount;
        while (abs < end) {
            (bytes32 asset, uint amount) = Execute.unpackAssetAmount(abs);
            if (asset == chainAsset) nativeAmount += amount;
            else debit(account, asset, amount);
            i = Execute.writeBalance(i, asset, amount);
            unchecked { abs += 72; }
        }
        uint funded = nativeAmount < value ? nativeAmount : value;
        remaining = value - funded;
        nativeAmount -= funded;
        if (remaining < budget) {
            nativeAmount += budget - remaining;
            remaining = budget;
        }
        if (nativeAmount != 0) {
            debit(account, chainAsset, nativeAmount);
            nativeDebit(nativeAmount);
        }
    }
    function cashin(bytes32 account, uint value) private {
        if (value == 0) return;
        credit(account, chainAsset, value);
        cashedIn(account, value);
    }

    /// @dev Input conversion to pipeline memory occurs before the timed region.
    /// staticCall measurements use identical original storage on every invocation.
    function measure(uint operation, bytes32 account, bytes calldata input, uint value)
        external returns (uint gasUsed, bytes memory output, uint remaining)
    {
        bytes memory state = operation == Credit ? bytes(input) : new bytes(0);
        uint cur = Cursors.wrap(input);
        uint start = gasleft();
        if (operation == Credit) creditState(account, state);
        else if (operation == Debit) output = debitInput(account, cur);
        else if (operation == Bootstrap) (output, remaining) = bootstrap(account, cur, value);
        else if (operation == Cashin) cashin(account, value);
        else if (operation == Root) {
            rooted(account, value, true);
            rooted(account, value, false);
        } else if (operation == RoundTrip) {
            rooted(account, value, true);
            (output, remaining) = bootstrap(account, cur, value);
            creditState(account, output);
            cashin(account, remaining);
            rooted(account, value, false);
        } else revert();
        gasUsed = start - gasleft();
    }
}

/// @dev Event signatures and cashin codes copied from Commander Main/Base and
/// its installed rootzero contracts 1.48.0 on 2026-10-05. Resulting balances.
contract CommanderLegacyLogs is CommanderLogComparison {
    uint private constant CashinCodes = 36 | (uint(0x80000001) << 32);
    event Balance(bytes32 indexed account, bytes32 asset, uint balance);
    event Activity(bytes32 indexed account, bytes32 subject, uint value, uint codes);
    event Rooted(bytes32 indexed account, uint deadline, uint value);

    function changed(bytes32 account, bytes32 asset, uint balance) internal override { emit Balance(account, asset, balance); }
    function stream(uint, bytes memory, uint) internal override {}
    function nativeDebit(uint) internal override {}
    function cashedIn(bytes32 account, uint amount) internal override { emit Activity(account, chainAsset, amount, CashinCodes); }
    function rooted(bytes32 account, uint value, bool before) internal override {
        if (!before) emit Rooted(account, 0, value);
    }
}

/// @dev Current log policy: account from Pipeline, per-operation deltas from lanes.
/// Constant endpoint IDs stand in for deployment metadata, outside timed work.
contract CommanderBlockLogs is CommanderLogComparison {
    function changed(bytes32, bytes32, uint) internal override {}
    function stream(uint operation, bytes memory data, uint cur) internal override {
        if (operation == Credit) Logs.memCopyWrap(Endpoint | 1, Keys.State, data);
        else if (operation == Debit) Logs.memWrap(Endpoint | 2, Keys.Output, data);
        else Logs.copyWrap(Endpoint | 3, Keys.Input, cur);
    }
    function nativeDebit(uint amount) internal override { Logs.balance(chainAsset, amount, Codes.AccountDebit); }
    function cashedIn(bytes32, uint amount) internal override { Logs.balance(chainAsset, amount, Codes.AccountCashin); }
    function rooted(bytes32 account, uint value, bool before) internal override {
        if (before) Logs.pipeline(account, value, Entities.Account);
    }
}

/// @dev Control for measuring incremental logging cost with the same storage work.
contract CommanderNoLogs is CommanderLogComparison {
    function changed(bytes32, bytes32, uint) internal override {}
    function stream(uint, bytes memory, uint) internal override {}
    function nativeDebit(uint) internal override {}
    function cashedIn(bytes32, uint) internal override {}
    function rooted(bytes32, uint, bool) internal override {}
}
