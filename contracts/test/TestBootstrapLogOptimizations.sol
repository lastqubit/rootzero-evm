// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;
import {BootstrapDebitLogReserved} from "./TestBootstrapDebitLogs.sol";
import {Blocks, Encoder, Execute, Logs, Sizes} from "../Codec.sol";
import {Codes} from "../utils/Codes.sol";
import {UnexpectedState} from "../utils/Errors.sol";

/// @dev Benchmark-only single-request fast path.
contract BootstrapLogSingle is BootstrapDebitLogReserved {
    function executeBootstrap(
        bytes32 account,
        bytes memory state,
        uint inputCur,
        uint value
    ) internal override returns (bool handled, bytes memory output, uint credit) {
        if (state.length != 0) revert UnexpectedState();
        (uint budget, uint balancesCur) = Blocks.unpackBootstrapExact(inputCur);
        (uint abs, uint end) = Execute.bounds(balancesCur, Sizes.AssetAmount);
        uint i;
        unchecked {
            (i, output) = Execute.allocateBalances((end - abs) / Sizes.AssetAmount);
        }

        uint logStart = i;
        uint logCur; // Zero while the log still shares the output buffer.
        uint nativeAmount;
        bool single = output.length == Sizes.Balance;
        while (abs < end) {
            (bytes32 asset, uint amount) = Execute.unpackAssetAmount(abs);
            if (asset == chainAsset) {
                nativeAmount += amount;
                if (!single && logCur == 0) (logStart, logCur) = forkLog(output, i - logStart);
            } else if (amount != 0) {
                debitAccount(account, asset, amount);
                if (logCur != 0) logCur = Encoder.writeBalanceAt(logCur, asset, amount);
            } else if (!single && logCur == 0) {
                (logStart, logCur) = forkLog(output, i - logStart);
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
            if (single && (nativeAmount != 0) && logCur == 0) {
                (bytes32 asset, uint amount) = Execute.unpackAssetAmount(end - Sizes.AssetAmount);
                if (asset == chainAsset || amount == 0) {
                    Logs.balance(chainAsset, nativeAmount, Codes.AccountBootstrap);
                    return (true, output, credit);
                }
            }
            if (logCur == 0) (logStart, logCur) = forkLog(output, output.length);
            logCur = Encoder.writeBalanceAt(logCur, chainAsset, nativeAmount);
        }

        if (single && logCur == 0) {
            (bytes32 asset, uint amount) = Execute.unpackAssetAmount(end - Sizes.AssetAmount);
            if (asset == chainAsset || amount == 0) return (true, output, credit);
        }
        if (logCur == 0) {
            if (output.length != 0) Logs.mem(Codes.AccountBootstrap, logStart, output.length);
        } else if (logCur != logStart) {
            Logs.mem(Codes.AccountBootstrap, logStart, logCur - logStart);
        }

        return (true, output, credit);
    }

    /// @dev Copy only the initialized output prefix. Reserve one block per request
    /// plus one combined native debit, so hook allocations cannot force growth.
    function forkLog(bytes memory output, uint prefixSize) private pure returns (uint start, uint cur) {
        bytes memory data = Encoder.allocate(output.length + Sizes.Balance);
        start = Encoder.pos(data, 0);
        cur = Encoder.copy(start, output, prefixSize);
    }
}

/// @dev Benchmark-only deferred allocation for empty debit prefixes.
contract BootstrapLogDeferred is BootstrapDebitLogReserved {
    function executeBootstrap(
        bytes32 account,
        bytes memory state,
        uint inputCur,
        uint value
    ) internal override returns (bool handled, bytes memory output, uint credit) {
        if (state.length != 0) revert UnexpectedState();
        (uint budget, uint balancesCur) = Blocks.unpackBootstrapExact(inputCur);
        (uint abs, uint end) = Execute.bounds(balancesCur, Sizes.AssetAmount);
        uint i;
        unchecked {
            (i, output) = Execute.allocateBalances((end - abs) / Sizes.AssetAmount);
        }

        uint logStart = i;
        uint logCur; // Zero while the log still shares the output buffer.
        uint nativeAmount;
        while (abs < end) {
            (bytes32 asset, uint amount) = Execute.unpackAssetAmount(abs);
            if (asset == chainAsset) {
                nativeAmount += amount;
                if (logCur == 0) (logStart, logCur) = forkLog(output, i - logStart);
            } else if (amount != 0) {
                debitAccount(account, asset, amount);
                if (logCur != 0) {
                    if (logCur == 1) (logStart, logCur) = allocateLog(output);
                    logCur = Encoder.writeBalanceAt(logCur, asset, amount);
                }
            } else if (logCur == 0) {
                (logStart, logCur) = forkLog(output, i - logStart);
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
            if (logCur == 0) (logStart, logCur) = forkLog(output, output.length);
            if (logCur == 1) {
                Logs.balance(chainAsset, nativeAmount, Codes.AccountBootstrap);
                return (true, output, credit);
            }
            logCur = Encoder.writeBalanceAt(logCur, chainAsset, nativeAmount);
        }

        if (logCur == 0) {
            if (output.length != 0) Logs.mem(Codes.AccountBootstrap, logStart, output.length);
        } else if (logCur > 1 && logCur != logStart) {
            Logs.mem(Codes.AccountBootstrap, logStart, logCur - logStart);
        }

        return (true, output, credit);
    }

    /// @dev Copy only the initialized output prefix. Reserve one block per request
    /// plus one combined native debit, so hook allocations cannot force growth.
    function forkLog(bytes memory output, uint prefixSize) private pure returns (uint start, uint cur) {
        if (prefixSize == 0) return (0, 1);
        (start, ) = allocateLog(output);
        cur = Encoder.copy(start, output, prefixSize);
    }
    function allocateLog(bytes memory output) private pure returns (uint start, uint cur) {
        bytes memory data = Encoder.allocate(output.length + Sizes.Balance);
        start = Encoder.pos(data, 0);
        return (start, start);
    }

}
