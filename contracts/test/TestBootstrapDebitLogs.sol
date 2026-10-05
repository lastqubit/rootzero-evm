// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

import {CommandBase, Specs} from "../commands/Base.sol";
import {DebitAccountHook} from "../core/Settlement.sol";
import {Runtime} from "../core/Runtime.sol";
import {Blocks, Cursors, Encoder, Execute, Logs, Sizes} from "../Codec.sol";
import {Codes} from "../utils/Codes.sol";
import {UnexpectedState} from "../utils/Errors.sol";
import {CommanderBootstrapLedger} from "./TestCommanderBootstrapComparison.sol";

/// @dev Experimental event-only writer. Funding/output body follows production;
/// logging alone changes to one AccountBootstrap stream of actual debit deltas.
abstract contract BootstrapDebitLogCandidate is CommandBase, DebitAccountHook, CommanderBootstrapLedger {
    constructor() Runtime(0) {
        command("bootstrap", Specs.Empty, Specs.Bootstrap, Specs.Balance, 0);
    }
    function enforceCaller(address caller) internal pure override returns (address) { return caller; }
    function nativeAsset() external view returns (bytes32) { return chainAsset; }
    function debitAccount(bytes32 account, bytes32 asset, uint amount) internal override {
        if (amount != 0) debitFrom(account, asset, amount);
    }
    function initLog(uint capacity) internal pure virtual returns (bytes memory data, uint cur);
    function appendLog(bytes memory data, uint cur, bytes32 asset, uint amount)
        internal pure virtual returns (bytes memory, uint);
    function emitLog(bytes memory data, uint cur) internal virtual;

    function measure(bytes32 account, bytes calldata input, uint value)
        external returns (uint gasUsed, bytes memory output, uint remaining)
    {
        bytes memory empty;
        uint cur = Cursors.wrap(input);
        uint start = gasleft();
        (, output, remaining) = executeBootstrap(account, empty, cur, value);
        gasUsed = start - gasleft();
    }

    function executeBootstrap(
        bytes32 account,
        bytes memory state,
        uint inputCur,
        uint value
    ) internal virtual returns (bool handled, bytes memory output, uint credit) {
        if (state.length != 0) revert UnexpectedState();
        (uint budget, uint balancesCur) = Blocks.unpackBootstrapExact(inputCur);
        (uint abs, uint end) = Execute.bounds(balancesCur, Sizes.AssetAmount);
        uint i;
        unchecked {
            (i, output) = Execute.allocateBalances((end - abs) / Sizes.AssetAmount);
        }
        (bytes memory logData, uint logCur) = initLog(end - abs + Sizes.Balance);

        uint nativeAmount;
        while (abs < end) {
            (bytes32 asset, uint amount) = Execute.unpackAssetAmount(abs);
            if (asset == chainAsset) {
                nativeAmount += amount;
            } else if (amount != 0) {
                debitAccount(account, asset, amount);
                (logData, logCur) = appendLog(logData, logCur, asset, amount);
            }
            i = Execute.writeBalance(i, asset, amount);
            unchecked {
                abs += Sizes.AssetAmount;
            }
        }

        uint funded = nativeAmount < value ? nativeAmount : value;
        credit = value - funded;
        nativeAmount -= funded;
        if (credit < budget) {
            nativeAmount += budget - credit;
            credit = budget;
        }
        if (nativeAmount != 0) {
            debitAccount(account, chainAsset, nativeAmount);
            (logData, logCur) = appendLog(logData, logCur, chainAsset, nativeAmount);
        }

        emitLog(logData, logCur);
        return (true, output, credit);
    }
}

/// @dev Ordinary Encoder writer, with n+1 blocks reserved before any debit hook.
contract BootstrapDebitLogWriter is BootstrapDebitLogCandidate {
    function initLog(uint capacity) internal pure override returns (bytes memory data, uint cur) {
        return Encoder.init(capacity);
    }
    function appendLog(bytes memory data, uint cur, bytes32 asset, uint amount)
        internal pure override returns (bytes memory, uint)
    {
        return Encoder.writeBalance(cur, data, asset, amount);
    }
    function emitLog(bytes memory data, uint cur) internal override {
        if (uint32(cur) == 0) return;
        data = Encoder.finish(cur, data);
        Logs.mem(Codes.AccountBootstrap, Encoder.pos(data, 0), data.length);
    }
}

/// @dev Fixed-capacity alternative: n+1 blocks prove capacity for every write.
/// Emits only the written prefix directly; never exposes the unused capacity as bytes.
contract BootstrapDebitLogReserved is BootstrapDebitLogCandidate {
    function initLog(uint capacity) internal pure override returns (bytes memory data, uint cur) {
        data = Encoder.allocate(capacity);
        cur = Encoder.pos(data, 0);
    }
    function appendLog(bytes memory data, uint cur, bytes32 asset, uint amount)
        internal pure override returns (bytes memory, uint)
    {
        return (data, Encoder.writeBalanceAt(cur, asset, amount));
    }
    function emitLog(bytes memory data, uint cur) internal override {
        uint abs = Encoder.pos(data, 0);
        if (cur == abs) return;
        Logs.mem(Codes.AccountBootstrap, abs, cur - abs);
    }
}
