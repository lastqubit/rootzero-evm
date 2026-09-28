// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

import {LegacyHeaders} from "./LegacyHeaders.sol";
import {BalanceConstraints, PositionConstraints, Position} from "../core/Types.sol";
import {InvalidBlock} from "../utils/Errors.sol";

// Frozen memory decoder for historical tests and benchmark baselines only.
// Production execute commands use Execute.
/// @title LegacyMemory
/// @notice Fixed-stride decoding for homogeneous block streams held in memory.
/// @dev The unpackers are intentionally unchecked beyond their exact header
/// comparison. Callers must obtain bounds with `bounds`, advance by the matching
/// complete encoded block size, and stop at the returned end position.
library LegacyMemory {
    /// @notice Return absolute bounds for a fixed-stride memory block stream.
    /// @dev DANGER: Empty streams are valid and `size` must be nonzero. The size
    /// must include the complete block header and payload.
    /// @param source Memory block stream.
    /// @param size Complete encoded size of each block.
    /// @return abs Absolute memory position of the first block header.
    /// @return end Absolute memory position immediately after the source.
    function bounds(bytes memory source, uint size) internal pure returns (uint abs, uint end) {
        uint len = source.length;
        uint remainder;
        assembly ("memory-safe") {
            remainder := mod(len, size)
            abs := add(source, 0x20)
            end := add(abs, len)
        }
        if (remainder != 0) revert InvalidBlock();
    }

    /// @notice Decode a LIMITS block at an in-bounds absolute memory position.
    /// @param abs Absolute block position obtained from bounds.
    /// @return limits Packed inclusive minimum (high 128 bits) and maximum (low 128 bits); meaning is context-dependent.
    function unpackLimits(uint abs) internal pure returns (uint limits) {
        uint64 actual;
        assembly ("memory-safe") {
            actual := shr(192, mload(abs))
            limits := mload(add(abs, 0x08))
        }
        if (actual != LegacyHeaders.Limits) revert InvalidBlock();
    }

    /// @notice Decode BALANCE_CONSTRAINTS at an in-bounds absolute memory position.
    function unpackBalanceConstraints(uint abs) internal pure returns (BalanceConstraints memory value) {
        uint64 head;
        assembly ("memory-safe") {
            head := shr(192, mload(abs))
            mstore(value, mload(add(abs, 0x08)))
            mstore(add(value, 0x20), mload(add(abs, 0x28)))
            mstore(add(value, 0x40), mload(add(abs, 0x48)))
        }
        if (head != LegacyHeaders.BalanceConstraints) revert InvalidBlock();
    }

    /// @notice Decode POSITION_CONSTRAINTS at an in-bounds absolute memory position.
    function unpackPositionConstraints(uint abs) internal pure returns (PositionConstraints memory value) {
        uint64 head;
        assembly ("memory-safe") {
            head := shr(192, mload(abs))
            mstore(value, mload(add(abs, 0x08)))
            mstore(add(value, 0x20), mload(add(abs, 0x28)))
            mstore(add(value, 0x40), mload(add(abs, 0x48)))
            mstore(add(value, 0x60), mload(add(abs, 0x68)))
        }
        if (head != LegacyHeaders.PositionConstraints) revert InvalidBlock();
    }

    /// @notice Decode a BALANCE block at an in-bounds absolute memory position.
    function unpackBalance(uint abs) internal pure returns (bytes32 asset, uint amount) {
        uint64 actual;
        assembly ("memory-safe") {
            actual := shr(192, mload(abs))
            asset := mload(add(abs, 0x08))
            amount := mload(add(abs, 0x28))
        }
        if (actual != LegacyHeaders.Balance) revert InvalidBlock();
    }

    /// @notice Decode a POSITION block at an in-bounds absolute memory position.
    function unpackPosition(
        uint abs
    ) internal pure returns (bytes32 asset, uint amount, bytes32 liability, uint debt, bytes32 counterparty) {
        uint64 actual;
        assembly ("memory-safe") {
            actual := shr(192, mload(abs))
            asset := mload(add(abs, 0x08))
            amount := mload(add(abs, 0x28))
            liability := mload(add(abs, 0x48))
            debt := mload(add(abs, 0x68))
            counterparty := mload(add(abs, 0x88))
        }
        if (actual != LegacyHeaders.Position) revert InvalidBlock();
    }

    /// @notice Decode a POSITION struct at an in-bounds absolute memory position.
    /// @dev Validates the exact header and preserves all fields, including counterparty.
    function unpackPositionValue(uint abs) internal pure returns (Position memory value) {
        (value.asset, value.amount, value.liability, value.debt, value.counterparty) = unpackPosition(abs);
    }

    /// @notice Decode a TRANSACTION block at an in-bounds absolute memory position.
    function unpackTransaction(uint abs) internal pure returns (bytes32 from, bytes32 to, bytes32 asset, uint amount) {
        uint64 actual;
        assembly ("memory-safe") {
            actual := shr(192, mload(abs))
            from := mload(add(abs, 0x08))
            to := mload(add(abs, 0x28))
            asset := mload(add(abs, 0x48))
            amount := mload(add(abs, 0x68))
        }
        if (actual != LegacyHeaders.Transaction) revert InvalidBlock();
    }
}
