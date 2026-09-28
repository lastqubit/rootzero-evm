// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

import {Cursors} from "../utils/Cursors.sol";
import {Encoder} from "./Encoder.sol";
import {Keys} from "./Keys.sol";
import {Headers} from "./Headers.sol";
import {Position} from "../core/Types.sol";
import {BALANCE_HEADER, BALANCE_CONSTRAINTS_HEADER, POSITION_HEADER, POSITION_CONSTRAINTS_HEADER} from "./Specs.sol";
import {INVALID_BLOCK, UNEXPECTED_VALUE, OUT_OF_RANGE, InvalidBlock} from "../utils/Errors.sol";

/// @title Execute
/// @notice Fixed-stride decoding, exact output writing, and batch checks for execute commands.
/// @dev Validate a homogeneous stream with bounds once, then advance abs by its
/// complete block size. Unpackers check exact headers without repeating bounds
/// checks. Plain abs unpackers read calldata; Memory suffixes read memory.
/// Calldata cursors require validated provenance and current <= end. Memory
/// sources must be live Solidity bytes allocations. No memory cursors are packed.
library Execute {
    // Once-per-stream validation. Empty streams are valid.

    /// @notice Validate fixed-stride divisibility and expose absolute calldata bounds.
    /// @dev Requires a validated cursor and nonzero size including the header.
    /// Does not inspect headers, advance cur, or repeat provenance checks.
    /// Metadata is ignored. A partial trailing block reverts before any hook runs.
    function bounds(uint cur, uint size) internal pure returns (uint abs, uint end) {
        return Cursors.bounds(cur, size);
    }

    /// @notice Validate fixed-stride divisibility and expose absolute memory bounds.
    /// @dev Requires a live bytes allocation and nonzero complete block size.
    /// Does not inspect headers or copy memory. A partial trailing block reverts
    /// before any hook runs. Memory addresses remain full-width.
    function bounds(bytes memory source, uint size) internal pure returns (uint abs, uint end) {
        uint remainder;
        assembly ("memory-safe") {
            let len := mload(source)
            remainder := mod(len, size)
            abs := add(source, 32)
            end := add(abs, len)
        }
        if (remainder != 0) revert InvalidBlock();
    }

    // Fixed calldata blocks. abs points at the header within a validated stream.

    /// @notice Decode a NODE at an in-bounds absolute calldata position.
    /// @dev Checks the exact header; caller establishes containment for 40 bytes.
    function unpackNode(uint abs) internal pure returns (uint node) {
        uint header;
        assembly ("memory-safe") {
            header := shr(192, calldataload(abs))
            node := calldataload(add(abs, 8))
        }
        if (header != Headers.Node) revert InvalidBlock();
    }

    /// @notice Decode an AMOUNT at an in-bounds absolute calldata position.
    /// @dev Checks the exact header; caller establishes containment for 72 bytes.
    function unpackAmount(uint abs) internal pure returns (bytes32 asset, uint amount) {
        uint header;
        assembly ("memory-safe") {
            header := shr(192, calldataload(abs))
            asset := calldataload(add(abs, 8))
            amount := calldataload(add(abs, 40))
        }
        if (header != Headers.Amount) revert InvalidBlock();
    }

    /// @notice Decode a BOOTSTRAP at an in-bounds absolute calldata position.
    /// @dev Checks the exact header; caller establishes containment for 104 bytes.
    function unpackBootstrap(uint abs) internal pure returns (bytes32 asset, uint amount, uint budget) {
        uint header;
        assembly ("memory-safe") {
            header := shr(192, calldataload(abs))
            asset := calldataload(add(abs, 8))
            amount := calldataload(add(abs, 40))
            budget := calldataload(add(abs, 72))
        }
        if (header != Headers.Bootstrap) revert InvalidBlock();
    }

    // Fixed memory blocks. abs points at the header within a validated stream.

    /// @notice Decode a BALANCE at an in-bounds absolute memory position.
    /// @dev Checks the exact header; caller establishes containment for 72 bytes.
    function unpackBalanceMemory(uint abs) internal pure returns (bytes32 asset, uint amount) {
        uint header;
        assembly ("memory-safe") {
            header := shr(192, mload(abs))
            asset := mload(add(abs, 8))
            amount := mload(add(abs, 40))
        }
        if (header != Headers.Balance) revert InvalidBlock();
    }

    /// @notice Decode a POSITION into an independent memory struct.
    /// @dev Checks the exact header; caller establishes containment for 168 bytes.
    /// Copies all five words, including counterparty. Hooks may mutate or retain
    /// this struct without modifying the source or a subsequently decoded value.
    function unpackPositionMemory(uint abs) internal pure returns (Position memory value) {
        uint header;
        assembly ("memory-safe") { header := shr(192, mload(abs)) }
        if (header != Headers.Position) revert InvalidBlock();
        assembly ("memory-safe") {
            // Solidity allocates the returned struct; copy directly into it.
            mcopy(value, add(abs, 8), 160)
        }
    }

    // Exact output allocation and sequential memory writes.

    /// @notice Allocate the final output for exactly count BALANCE blocks.
    /// @dev Requires count <= uint32.max, as established by a validated input
    /// stream. Rejects encoded sizes exceeding uint32.max. The result has its
    /// final length but uninitialized contents: fill every block before exposing
    /// it. Hooks may allocate between writes because each write stays inside
    /// the reserved logical range. No growable cursor or finalization is needed.
    /// @return abs Absolute memory position of the first output block.
    /// @return output Exactly sized BALANCE stream with zero trailing padding.
    function allocateBalances(uint count) internal pure returns (uint abs, bytes memory output) {
        unchecked { output = Encoder.allocate(count * 72); }
        abs = Encoder.pos(output, 0);
    }

    /// @notice Write one BALANCE into reserved memory and return the next position.
    /// @dev Requires at least 72 writable bytes at abs. Performs no bounds check,
    /// growth, or allocation. All stores remain within those 72 bytes.
    /// @param abs Absolute output memory position, not a packed cursor.
    function writeBalance(uint abs, bytes32 asset, uint amount) internal pure returns (uint nextAbs) {
        abs = Encoder.writeHeader(abs, Keys.Balance, 64);
        abs = Encoder.write32(abs, asset);
        nextAbs = Encoder.write32(abs, bytes32(amount));
    }

    // Paired state/constraint streams. Validate without unpacking or copying.

    /// @notice Validate every memory BALANCE against its paired calldata constraint.
    /// @dev Requires a validated input cursor and live state allocation. Validates
    /// stream sizes before any block, then headers, identifiers, and quantities
    /// in that order. Leaves state unchanged and does not allocate or advance inputCur.
    function checkBalances(bytes memory state, uint inputCur) internal pure {
        assembly ("memory-safe") {
            function fail(selector) {
                mstore(0, selector)
                revert(28, 4)
            }
            let inputSize := sub(and(shr(32, inputCur), 0xffffffff), and(inputCur, 0xffffffff))
            let size := mload(state)
            // floor(inputSize / 104) * 72 <= inputSize, so multiplication cannot overflow.
            if or(mod(inputSize, 104), iszero(eq(size, mul(div(inputSize, 104), 72)))) {
                fail(INVALID_BLOCK)
            }
            let start := add(state, 32)
            let end := add(start, size)
            let q := and(inputCur, 0xffffffff)
            // Strides include each block's eight-byte header.
            for {
                let p := start
            } lt(p, end) {
                p := add(p, 72)
                q := add(q, 104)
            } {
                if or(
                    iszero(eq(shr(192, mload(p)), BALANCE_HEADER)),
                    iszero(eq(shr(192, calldataload(q)), BALANCE_CONSTRAINTS_HEADER))
                ) {
                    fail(INVALID_BLOCK)
                }
                if iszero(eq(mload(add(p, 0x08)), calldataload(add(q, 0x08)))) {
                    fail(UNEXPECTED_VALUE)
                }
                let amount := mload(add(p, 0x28))
                if or(lt(amount, calldataload(add(q, 0x28))), gt(amount, calldataload(add(q, 0x48)))) {
                    fail(OUT_OF_RANGE)
                }
            }
        }
    }

    /// @notice Validate every memory POSITION against its paired calldata constraint.
    /// @dev Requires a validated input cursor and live state allocation. Validates
    /// stream sizes before any block, then headers, identifiers, and quantities
    /// in that order. Leaves state unchanged and does not allocate or advance inputCur.
    function checkPositions(bytes memory state, uint inputCur) internal pure {
        assembly ("memory-safe") {
            function fail(selector) {
                mstore(0, selector)
                revert(28, 4)
            }
            let inputSize := sub(and(shr(32, inputCur), 0xffffffff), and(inputCur, 0xffffffff))
            let size := mload(state)
            if mod(size, 168) {
                fail(INVALID_BLOCK)
            }
            // floor(size / 168) * 136 <= size, so multiplication cannot overflow.
            if iszero(eq(inputSize, mul(div(size, 168), 136))) {
                fail(INVALID_BLOCK)
            }
            let start := add(state, 32)
            let end := add(start, size)
            let q := and(inputCur, 0xffffffff)
            // Strides include each block's eight-byte header.
            for {
                let p := start
            } lt(p, end) {
                p := add(p, 168)
                q := add(q, 136)
            } {
                if or(
                    iszero(eq(shr(192, mload(p)), POSITION_HEADER)),
                    iszero(eq(shr(192, calldataload(q)), POSITION_CONSTRAINTS_HEADER))
                ) {
                    fail(INVALID_BLOCK)
                }
                if or(
                    xor(mload(add(p, 0x08)), calldataload(add(q, 0x08))),
                    xor(mload(add(p, 0x48)), calldataload(add(q, 0x48)))
                ) {
                    fail(UNEXPECTED_VALUE)
                }
                if or(
                    lt(mload(add(p, 0x28)), calldataload(add(q, 0x28))),
                    gt(mload(add(p, 0x68)), calldataload(add(q, 0x68)))
                ) {
                    fail(OUT_OF_RANGE)
                }
            }
        }
    }
}
