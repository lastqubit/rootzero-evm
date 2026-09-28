// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;
import {Encoder} from "../codec/Encoder.sol";
import {Keys} from "../codec/Keys.sol";
/// @dev Frozen offset writer comparison baseline. Production uses cursor writers.
library ReservedBlockEncoder {
    // Reserved writers: fixed-size blocks, then composites (default before Wrap).

    /// @notice Write a BALANCE block at byte offset i in dst.
    /// @dev Reserve 72 bytes before calling. No bounds checks, allocation, or
    /// resizing; writes exactly 72 bytes and needs no trailing scratch space.
    /// @param dst Caller-reserved destination buffer.
    /// @param i Relative byte offset of the BALANCE header.
    /// @param asset Asset identifier, encoded unchanged.
    /// @param amount Full-width balance amount, encoded unchanged.
    /// @return nextI Relative byte offset immediately after the encoded block.
    function writeBalance(bytes memory dst, uint i, bytes32 asset, uint amount) internal pure returns (uint nextI) {
        uint abs = Encoder.writeHeader(Encoder.pos(dst, i), Keys.Balance, 64);
        abs = Encoder.write32(abs, asset);
        Encoder.write32(abs, bytes32(amount));
        unchecked { nextI = i + 72; }
    }

    /// @notice Write a CONTEXT by copying two complete BYTES blocks from memory.
    /// @dev Each source must be exactly one validated BYTES block, including its
    /// eight-byte header. Even an empty payload requires a complete BYTES header.
    /// Reserve 40 + state.length + input.length bytes; the complete size
    /// must fit uint32. Sources must not overlap the destination. No bounds or
    /// header checks, allocation, or resizing. No trailing scratch space is needed.
    /// @return nextI Relative byte offset immediately after the encoded block.
    function writeContext(
        bytes memory dst,
        uint i,
        bytes32 account,
        bytes memory state,
        bytes memory input
    ) internal pure returns (uint nextI) {
        uint stateSize = state.length;
        uint inputSize = input.length;
        uint abs = Encoder.pos(dst, i);
        unchecked {
            abs = Encoder.writeHeader(abs, Keys.Context, 32 + stateSize + inputSize);
            abs = Encoder.write32(abs, account);
            abs = Encoder.copy(abs, state, stateSize);
            Encoder.copy(abs, input, inputSize);
            nextI = i + 40 + stateSize + inputSize;
        }
    }

    /// @notice Write a CONTEXT by copying two complete BYTES blocks from calldata.
    /// @dev Same destination and complete-block requirements as the memory overload.
    /// Both cursors must satisfy current <= end <= calldatasize and select exactly
    /// one validated BYTES block. Metadata is ignored; cursors are not advanced.
    /// @param stateCur Cursor over one complete BYTES block, including its header.
    /// @param inputCur Cursor over one complete BYTES block, including its header.
    /// @return nextI Relative byte offset immediately after the encoded block.
    function writeContext(bytes memory dst, uint i, bytes32 account, uint stateCur, uint inputCur) internal pure returns (uint nextI) {
        uint stateSize = Encoder.length(stateCur);
        uint inputSize = Encoder.length(inputCur);
        uint abs = Encoder.pos(dst, i);
        unchecked {
            abs = Encoder.writeHeader(abs, Keys.Context, 32 + stateSize + inputSize);
            abs = Encoder.write32(abs, account);
            abs = Encoder.copy(abs, uint32(stateCur), stateSize);
            Encoder.copy(abs, uint32(inputCur), inputSize);
            nextI = i + 40 + stateSize + inputSize;
        }
    }

    /// @notice Write a CONTEXT at byte offset i, wrapping memory payloads in BYTES headers.
    /// @dev Unchecked destination: reserve 56 + state.length + input.length bytes
    /// plus 24 bytes of writable header scratch after the block. Scratch may be
    /// overwritten. The complete size must fit uint32, and sources must not overlap
    /// the destination or scratch. Does not allocate, resize dst, or validate streams.
    /// @return nextI Relative byte offset immediately after the encoded block.
    function writeContextWrap(
        bytes memory dst,
        uint i,
        bytes32 account,
        bytes memory state,
        bytes memory input
    ) internal pure returns (uint nextI) {
        uint stateSize = state.length;
        uint inputSize = input.length;
        uint abs = Encoder.pos(dst, i);
        unchecked {
            abs = Encoder.writeHeader(abs, Keys.Context, 48 + stateSize + inputSize);
            abs = Encoder.write32(abs, account);
            abs = Encoder.wrap(abs, Keys.Bytes, state, stateSize);
            Encoder.wrap(abs, Keys.Bytes, input, inputSize);
            nextI = i + 56 + stateSize + inputSize;
        }
    }

    /// @notice Write a CONTEXT by wrapping validated calldata payload cursors in BYTES headers.
    /// @dev Same destination, size, and scratch preconditions as the memory overload.
    /// Requires current <= end <= calldatasize for both cursors. Copies remaining
    /// ranges, ignores metadata, and leaves cursors unchanged. No bounds checks.
    /// @return nextI Relative byte offset immediately after the encoded block.
    function writeContextWrap(bytes memory dst, uint i, bytes32 account, uint stateCur, uint inputCur) internal pure returns (uint nextI) {
        uint stateSize = Encoder.length(stateCur);
        uint inputSize = Encoder.length(inputCur);
        uint abs = Encoder.pos(dst, i);
        unchecked {
            abs = Encoder.writeHeader(abs, Keys.Context, 48 + stateSize + inputSize);
            abs = Encoder.write32(abs, account);
            abs = Encoder.wrap(abs, Keys.Bytes, uint32(stateCur), stateSize);
            Encoder.wrap(abs, Keys.Bytes, uint32(inputCur), inputSize);
            nextI = i + 56 + stateSize + inputSize;
        }
    }

}
