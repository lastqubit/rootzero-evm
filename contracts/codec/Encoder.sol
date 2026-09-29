// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

import {Keys} from "./Keys.sol";
import {ValueOverflow} from "../utils/Errors.sol";

/// @title Encoder
/// @notice Specialized encoders with memory and calldata-cursor overloads.
/// @dev Memory payloads use bytes; uint source cursors are validated packed calldata ranges.
/// Creators allocate only the final block. Cursor-first writers manage growable
/// buffers, including allocation, reservation, growth, and finalization.
/// Neither inspects nested stream contents. Absolute positions here refer to memory,
/// except the source position of the calldata copy primitive.
/// Creators always construct blocks from values and payloads, adding child headers.
/// Default composite writers copy complete children; their Wrap variants add child headers.
/// Cursor parameters use stateCur/inputCur in both; function names and NatSpec
/// specify whether their ranges include child headers.
library Encoder {
    // General primitives: allocation, positions, sequential writes, and copies.

    /// @dev Allocate an uninitialized uint32-sized result with zero padding.
    /// Use pos(value, 0) for the first write position. Fill all logical bytes before
    /// exposing the result. Only the rounded final allocation is retained: writes
    /// may interleave allocations if they stay inside that owned extent. Any
    /// scratch beyond it must be used before further allocations.
    function allocate(uint size) internal pure returns (bytes memory value) {
        if (size > type(uint32).max) revert ValueOverflow();
        assembly ("memory-safe") {
            value := mload(0x40)
            let abs := add(value, 32)
            mstore(value, size)
            mstore(add(abs, size), 0)
            mstore(0x40, add(abs, and(add(size, 31), not(31))))
        }
    }

    /// @dev Return the unchecked absolute memory address at byte offset i in dst.
    /// The caller must reserve sufficient memory before writing at this position.
    function pos(bytes memory dst, uint i) internal pure returns (uint abs) {
        assembly ("memory-safe") {
            abs := add(add(dst, 32), i)
        }
    }

    /// @dev Remaining length of a validated calldata cursor; ignores metadata.
    function length(uint cur) internal pure returns (uint size) {
        uint abs = uint32(cur);
        unchecked {
            size = uint32(cur >> 32) - abs;
        }
    }

    /// @dev Write a header and return its payload position. Requires size <= uint32.max.
    /// Also overwrites the next 24 bytes: reserve them or use temporary free memory
    /// immediately after a fresh result. Pointer arithmetic is unchecked.
    function writeHeader(uint abs, bytes4 key, uint size) internal pure returns (uint nextAbs) {
        uint keyWord = uint32(key);
        assembly ("memory-safe") {
            mstore(abs, or(shl(224, keyWord), shl(192, size)))
            nextAbs := add(abs, 8)
        }
    }

    /// @dev Write a word to reserved memory and return the position after it.
    function write32(uint abs, bytes32 value) internal pure returns (uint nextAbs) {
        assembly ("memory-safe") {
            mstore(abs, value)
            nextAbs := add(abs, 32)
        }
    }

    /// @dev Copy a memory range and return the next destination. Source and destination
    /// must be valid; composite callers must keep sources disjoint from all writes.
    function copy(uint abs, bytes memory source, uint size) internal pure returns (uint nextAbs) {
        assembly ("memory-safe") {
            mcopy(abs, add(source, 32), size)
            nextAbs := add(abs, size)
        }
    }

    /// @dev Copy a validated absolute calldata range to reserved memory and advance.
    function copy(uint abs, uint sourceAbs, uint size) internal pure returns (uint nextAbs) {
        assembly ("memory-safe") {
            calldatacopy(abs, sourceAbs, size)
            nextAbs := add(abs, size)
        }
    }

    /// @dev Copy all source bytes unchanged, including any existing block header.
    function copy(uint abs, bytes memory source) internal pure returns (uint nextAbs) {
        return copy(abs, source, source.length);
    }

    /// @dev Copy a validated cursor's remaining range unchanged and advance destination.
    function copy(uint abs, uint cur) internal pure returns (uint nextAbs) {
        return copy(abs, uint32(cur), length(cur));
    }

    /// @dev Wrap size memory bytes with a header and advance past the whole block.
    /// Requires size <= payload.length and size <= uint32.max; inherits header
    /// scratch and copy preconditions. Use when the caller already knows the size.
    function wrap(uint abs, bytes4 key, bytes memory payload, uint size) internal pure returns (uint nextAbs) {
        return copy(writeHeader(abs, key, size), payload, size);
    }

    /// @dev Wrap a validated absolute calldata range and advance past the block.
    /// Requires size <= uint32.max; inherits header scratch and copy preconditions.
    function wrap(uint abs, bytes4 key, uint sourceAbs, uint size) internal pure returns (uint nextAbs) {
        return copy(writeHeader(abs, key, size), sourceAbs, size);
    }

    /// @dev Wrap a memory payload with a new header and advance past the whole block.
    /// Inherits writeHeader scratch requirements and copy source/destination preconditions.
    function wrap(uint abs, bytes4 key, bytes memory payload) internal pure returns (uint nextAbs) {
        return wrap(abs, key, payload, payload.length);
    }

    /// @dev Wrap a validated calldata payload cursor with a new header and advance.
    /// Inherits writeHeader scratch requirements and copy source/destination preconditions.
    function wrap(uint abs, bytes4 key, uint cur) internal pure returns (uint nextAbs) {
        return wrap(abs, key, uint32(cur), length(cur));
    }

    // Growable buffers: allocation, initialization, growth, reservation, finalization.

    /// @dev Allocate uninitialized capacity plus one retained scratch word and copy
    /// only the written prefix. Requires written <= capacity <= uint32.max and
    /// written <= dst.length. Unwritten bytes must never be exposed or read.
    function grow(bytes memory dst, uint written, uint capacity) internal pure returns (bytes memory value) {
        assembly ("memory-safe") {
            value := mload(0x40)
            let padded := add(and(add(capacity, 31), not(31)), 32)
            mstore(value, padded)
            mstore(0x40, add(add(value, 32), padded))
            mcopy(add(value, 32), add(dst, 32), written)
        }
    }

    /// @notice Initialize an allocated, growable writer and return its buffer and cursor.
    /// @dev Low 32 bits hold the relative written position; the next 32 hold
    /// logical capacity. Allocate capacity and retained scratch immediately, even for zero
    /// capacity. The returned pair is the only valid starting state for reserve.
    function init(uint capacity) internal pure returns (bytes memory dst, uint cur) {
        if (capacity > type(uint32).max) revert ValueOverflow();
        cur = capacity << 32;
        bytes memory empty;
        dst = grow(empty, 0, capacity);
    }

    /// @dev Cold path, reached only when size exceeds remaining capacity.
    function grow(uint cur, bytes memory dst, uint size) private pure returns (bytes memory value, uint nextCur) {
        uint written = uint32(cur);
        uint capacity = uint32(cur >> 32);
        uint required = written + size;
        if (required > type(uint32).max) revert ValueOverflow();
        unchecked {
            capacity = capacity == 0 ? 64 : capacity * 2;
            while (capacity < required) capacity *= 2;
        }
        if (capacity > type(uint32).max) revert ValueOverflow();
        nextCur = (cur & ~(uint(type(uint32).max) << 32)) | (capacity << 32);
        value = grow(dst, written, capacity);
    }

    /// @notice Reserve size logical bytes and return the updated writer and write address.
    /// @dev Requires a matching allocated pair and position <= capacity. Fill
    /// each reservation before growth/finalization; keep both returned values.
    /// The space check proves advancing cannot carry into the capacity lane.
    /// Metadata above bit 63 is preserved. A retained scratch word permits
    /// header writes without reserving additional logical bytes.
    /// @return value Original or relocated destination; always retain this return.
    /// @return abs Absolute memory address at the beginning of the reservation.
    /// @return nextCur Advanced relative cursor, with updated capacity after growth.
    function reserve(
        uint cur,
        bytes memory dst,
        uint size
    ) internal pure returns (bytes memory value, uint abs, uint nextCur) {
        uint available;
        unchecked {
            available = uint32(cur >> 32) - uint(uint32(cur));
        }
        if (size > available) (dst, cur) = grow(cur, dst, size);
        abs = pos(dst, uint32(cur));
        unchecked {
            nextCur = cur + size;
        }
        value = dst;
    }

    /// @notice Return the written prefix of an initialized writer.
    /// @dev End the writer lifecycle, exposing its initialized prefix and zero
    /// padding. Works in place even when unused; never append after finish.
    function finish(uint cur, bytes memory dst) internal pure returns (bytes memory value) {
        uint written = uint32(cur);
        assembly ("memory-safe") {
            mstore(dst, written)
            mstore(add(add(dst, 32), written), 0)
        }
        value = dst;
    }

    // Cursor writers: reserve and write, returning the buffer followed by the updated cursor.

    /// @notice Append ACCOUNT, preserving field order and full-width values.
    /// @dev Inherits reserve's initialized-writer requirements.
    function writeAccount(
        uint cur,
        bytes memory dst,
        bytes32 account
    ) internal pure returns (bytes memory value, uint nextCur) {
        uint abs;
        (value, abs, nextCur) = reserve(cur, dst, 40);
        abs = writeHeader(abs, Keys.Account, 32);
        write32(abs, account);
    }

    /// @notice Append ASSET, preserving field order and full-width values.
    /// @dev Inherits reserve's initialized-writer requirements.
    function writeAsset(
        uint cur,
        bytes memory dst,
        bytes32 asset
    ) internal pure returns (bytes memory value, uint nextCur) {
        uint abs;
        (value, abs, nextCur) = reserve(cur, dst, 40);
        abs = writeHeader(abs, Keys.Asset, 32);
        write32(abs, asset);
    }

    /// @notice Append NODE, preserving field order and full-width values.
    /// @dev Inherits reserve's initialized-writer requirements.
    function writeNode(uint cur, bytes memory dst, uint node) internal pure returns (bytes memory value, uint nextCur) {
        uint abs;
        (value, abs, nextCur) = reserve(cur, dst, 40);
        abs = writeHeader(abs, Keys.Node, 32);
        write32(abs, bytes32(node));
    }

    /// @notice Append ENTITY, preserving field order and full-width values.
    /// @dev Inherits reserve's initialized-writer requirements.
    function writeEntity(uint cur, bytes memory dst, uint entity) internal pure returns (bytes memory value, uint nextCur) {
        uint abs;
        (value, abs, nextCur) = reserve(cur, dst, 40);
        abs = writeHeader(abs, Keys.Entity, 32);
        write32(abs, bytes32(entity));
    }

    /// @notice Append STATUS, preserving field order and full-width values.
    /// @dev Inherits reserve's initialized-writer requirements.
    function writeStatus(
        uint cur,
        bytes memory dst,
        uint code
    ) internal pure returns (bytes memory value, uint nextCur) {
        uint abs;
        (value, abs, nextCur) = reserve(cur, dst, 40);
        abs = writeHeader(abs, Keys.Status, 32);
        write32(abs, bytes32(code));
    }

    /// @notice Append one CODES block containing packed identifiers.
    /// @dev Inherits reserve's initialized-writer requirements. Preserves all bits;
    /// performs no code-packing or semantic validation.
    function writeCodes(
        uint cur,
        bytes memory dst,
        uint codes
    ) internal pure returns (bytes memory value, uint nextCur) {
        uint abs;
        (value, abs, nextCur) = reserve(cur, dst, 40);
        abs = writeHeader(abs, Keys.Codes, 32);
        write32(abs, bytes32(codes));
    }

    /// @notice Append LIMITS, preserving field order and full-width values.
    /// @dev Inherits reserve's initialized-writer requirements.
    function writeLimits(
        uint cur,
        bytes memory dst,
        uint limits
    ) internal pure returns (bytes memory value, uint nextCur) {
        uint abs;
        (value, abs, nextCur) = reserve(cur, dst, 40);
        abs = writeHeader(abs, Keys.Limits, 32);
        write32(abs, bytes32(limits));
    }

    /// @notice Append AMOUNT, preserving field order and full-width values.
    /// @dev Inherits reserve's initialized-writer requirements.
    function writeAmount(
        uint cur,
        bytes memory dst,
        bytes32 asset,
        uint amount
    ) internal pure returns (bytes memory value, uint nextCur) {
        uint abs;
        (value, abs, nextCur) = reserve(cur, dst, 72);
        abs = writeHeader(abs, Keys.Amount, 64);
        abs = write32(abs, asset);
        write32(abs, bytes32(amount));
    }

    /// @notice Append BALANCE to a growable writer and return its updated state.
    /// @dev Inherits reserve's writer lifecycle requirements.
    function writeBalance(
        uint cur,
        bytes memory dst,
        bytes32 asset,
        uint amount
    ) internal pure returns (bytes memory value, uint nextCur) {
        uint abs;
        (value, abs, nextCur) = reserve(cur, dst, 72);
        abs = writeHeader(abs, Keys.Balance, 64);
        abs = write32(abs, asset);
        write32(abs, bytes32(amount));
    }

    /// @notice Append ASSETLIABILITY, preserving field order and full-width values.
    /// @dev Inherits reserve's initialized-writer requirements.
    function writeAssetLiability(
        uint cur,
        bytes memory dst,
        bytes32 asset,
        bytes32 liability
    ) internal pure returns (bytes memory value, uint nextCur) {
        uint abs;
        (value, abs, nextCur) = reserve(cur, dst, 72);
        abs = writeHeader(abs, Keys.AssetLiability, 64);
        abs = write32(abs, asset);
        write32(abs, liability);
    }

    /// @notice Append ACCOUNTASSET, preserving field order and full-width values.
    /// @dev Inherits reserve's initialized-writer requirements.
    function writeAccountAsset(
        uint cur,
        bytes memory dst,
        bytes32 account,
        bytes32 asset
    ) internal pure returns (bytes memory value, uint nextCur) {
        uint abs;
        (value, abs, nextCur) = reserve(cur, dst, 72);
        abs = writeHeader(abs, Keys.AccountAsset, 64);
        abs = write32(abs, account);
        write32(abs, asset);
    }

    /// @notice Append HOSTASSET, preserving field order and full-width values.
    /// @dev Inherits reserve's initialized-writer requirements.
    function writeHostAsset(
        uint cur,
        bytes memory dst,
        uint host,
        bytes32 asset
    ) internal pure returns (bytes memory value, uint nextCur) {
        uint abs;
        (value, abs, nextCur) = reserve(cur, dst, 72);
        abs = writeHeader(abs, Keys.HostAsset, 64);
        abs = write32(abs, bytes32(host));
        write32(abs, asset);
    }

    /// @notice Append ALLOCATION, preserving field order and full-width values.
    /// @dev Inherits reserve's initialized-writer requirements.
    function writeAllocation(
        uint cur,
        bytes memory dst,
        uint host,
        bytes32 asset,
        uint amount
    ) internal pure returns (bytes memory value, uint nextCur) {
        uint abs;
        (value, abs, nextCur) = reserve(cur, dst, 104);
        abs = writeHeader(abs, Keys.Allocation, 96);
        abs = write32(abs, bytes32(host));
        abs = write32(abs, asset);
        write32(abs, bytes32(amount));
    }

    /// @notice Append ALLOWANCE, preserving field order and full-width values.
    /// @dev Inherits reserve's initialized-writer requirements.
    function writeAllowance(
        uint cur,
        bytes memory dst,
        uint host,
        bytes32 asset,
        uint amount
    ) internal pure returns (bytes memory value, uint nextCur) {
        uint abs;
        (value, abs, nextCur) = reserve(cur, dst, 104);
        abs = writeHeader(abs, Keys.Allowance, 96);
        abs = write32(abs, bytes32(host));
        abs = write32(abs, asset);
        write32(abs, bytes32(amount));
    }

    /// @notice Append CUSTODY, preserving field order and full-width values.
    /// @dev Inherits reserve's initialized-writer requirements.
    function writeCustody(
        uint cur,
        bytes memory dst,
        uint host,
        bytes32 asset,
        uint amount
    ) internal pure returns (bytes memory value, uint nextCur) {
        uint abs;
        (value, abs, nextCur) = reserve(cur, dst, 104);
        abs = writeHeader(abs, Keys.Custody, 96);
        abs = write32(abs, bytes32(host));
        abs = write32(abs, asset);
        write32(abs, bytes32(amount));
    }

    /// @notice Append ACCOUNTAMOUNT, preserving field order and full-width values.
    /// @dev Inherits reserve's initialized-writer requirements.
    function writeAccountAmount(
        uint cur,
        bytes memory dst,
        bytes32 account,
        bytes32 asset,
        uint amount
    ) internal pure returns (bytes memory value, uint nextCur) {
        uint abs;
        (value, abs, nextCur) = reserve(cur, dst, 104);
        abs = writeHeader(abs, Keys.AccountAmount, 96);
        abs = write32(abs, account);
        abs = write32(abs, asset);
        write32(abs, bytes32(amount));
    }

    /// @notice Append HOSTAMOUNT, preserving field order and full-width values.
    /// @dev Inherits reserve's initialized-writer requirements.
    function writeHostAmount(
        uint cur,
        bytes memory dst,
        uint host,
        bytes32 asset,
        uint amount
    ) internal pure returns (bytes memory value, uint nextCur) {
        uint abs;
        (value, abs, nextCur) = reserve(cur, dst, 104);
        abs = writeHeader(abs, Keys.HostAmount, 96);
        abs = write32(abs, bytes32(host));
        abs = write32(abs, asset);
        write32(abs, bytes32(amount));
    }

    /// @notice Append HOSTACCOUNTASSET, preserving field order and full-width values.
    /// @dev Inherits reserve's initialized-writer requirements.
    function writeHostAccountAsset(
        uint cur,
        bytes memory dst,
        uint host,
        bytes32 account,
        bytes32 asset
    ) internal pure returns (bytes memory value, uint nextCur) {
        uint abs;
        (value, abs, nextCur) = reserve(cur, dst, 104);
        abs = writeHeader(abs, Keys.HostAccountAsset, 96);
        abs = write32(abs, bytes32(host));
        abs = write32(abs, account);
        write32(abs, asset);
    }

    /// @notice Append QUOTE, preserving field order and full-width values.
    /// @dev Inherits reserve's initialized-writer requirements.
    function writeQuote(
        uint cur,
        bytes memory dst,
        bytes32 asset,
        uint amount,
        bytes32 liability,
        uint debt
    ) internal pure returns (bytes memory value, uint nextCur) {
        uint abs;
        (value, abs, nextCur) = reserve(cur, dst, 136);
        abs = writeHeader(abs, Keys.Quote, 128);
        abs = write32(abs, asset);
        abs = write32(abs, bytes32(amount));
        abs = write32(abs, liability);
        write32(abs, bytes32(debt));
    }

    /// @notice Append TRANSACTION, preserving field order and full-width values.
    /// @dev Inherits reserve's initialized-writer requirements.
    function writeTransaction(
        uint cur,
        bytes memory dst,
        bytes32 from,
        bytes32 to,
        bytes32 asset,
        uint amount
    ) internal pure returns (bytes memory value, uint nextCur) {
        uint abs;
        (value, abs, nextCur) = reserve(cur, dst, 136);
        abs = writeHeader(abs, Keys.Transaction, 128);
        abs = write32(abs, from);
        abs = write32(abs, to);
        abs = write32(abs, asset);
        write32(abs, bytes32(amount));
    }

    /// @notice Append HOSTACCOUNTAMOUNT, preserving field order and full-width values.
    /// @dev Inherits reserve's initialized-writer requirements.
    function writeHostAccountAmount(
        uint cur,
        bytes memory dst,
        uint host,
        bytes32 account,
        bytes32 asset,
        uint amount
    ) internal pure returns (bytes memory value, uint nextCur) {
        uint abs;
        (value, abs, nextCur) = reserve(cur, dst, 136);
        abs = writeHeader(abs, Keys.HostAccountAmount, 128);
        abs = write32(abs, bytes32(host));
        abs = write32(abs, account);
        abs = write32(abs, asset);
        write32(abs, bytes32(amount));
    }

    /// @notice Append POSITION, preserving field order and full-width values.
    /// @dev Inherits reserve's initialized-writer requirements.
    function writePosition(
        uint cur,
        bytes memory dst,
        bytes32 asset,
        uint amount,
        bytes32 liability,
        uint debt,
        bytes32 counterparty
    ) internal pure returns (bytes memory value, uint nextCur) {
        uint abs;
        (value, abs, nextCur) = reserve(cur, dst, 168);
        abs = writeHeader(abs, Keys.Position, 160);
        abs = write32(abs, asset);
        abs = write32(abs, bytes32(amount));
        abs = write32(abs, liability);
        abs = write32(abs, bytes32(debt));
        write32(abs, counterparty);
    }

    // Payload blocks: generic key followed by named wrappers.

    /// @notice Append a complete validated calldata block without changing its header.
    /// @dev Source must select the complete block in calldata. Does not revalidate or advance it.
    function writeBlock(
        uint cur,
        bytes memory dst,
        uint dataCur
    ) internal pure returns (bytes memory value, uint nextCur) {
        uint size = length(dataCur);
        uint abs;
        (value, abs, nextCur) = reserve(cur, dst, size);
        copy(abs, uint32(dataCur), size);
    }

    /// @notice Append a block with key and the supplied memory payload.
    /// @dev Does not validate schema bounds or payload contents. Inherits reserve
    /// and copy preconditions; source ranges must be disjoint from writes.
    function writeBlock(
        uint cur,
        bytes memory dst,
        bytes4 key,
        bytes memory data
    ) internal pure returns (bytes memory value, uint nextCur) {
        uint payloadSize = data.length;
        uint abs;
        (value, abs, nextCur) = reserve(cur, dst, 8 + payloadSize);
        wrap(abs, key, data, payloadSize);
    }

    /// @notice Append a block with key and the supplied validated calldata-cursor payload.
    /// @dev Does not validate schema bounds or payload contents. Inherits reserve
    /// and copy preconditions; source ranges must be disjoint from writes.
    function writeBlock(
        uint cur,
        bytes memory dst,
        bytes4 key,
        uint dataCur
    ) internal pure returns (bytes memory value, uint nextCur) {
        uint payloadSize = length(dataCur);
        uint abs;
        (value, abs, nextCur) = reserve(cur, dst, 8 + payloadSize);
        wrap(abs, key, uint32(dataCur), payloadSize);
    }

    /// @notice Append LIST from a memory payload; empty payloads are allowed.
    /// @dev Inherits writeBlock's lifecycle and source requirements.
    function writeList(
        uint cur,
        bytes memory dst,
        bytes memory data
    ) internal pure returns (bytes memory value, uint nextCur) {
        return writeBlock(cur, dst, Keys.List, data);
    }

    /// @notice Append LIST from a validated calldata payload cursor; empty payloads are allowed.
    /// @dev Inherits writeBlock's lifecycle and source requirements.
    function writeList(
        uint cur,
        bytes memory dst,
        uint dataCur
    ) internal pure returns (bytes memory value, uint nextCur) {
        return writeBlock(cur, dst, Keys.List, dataCur);
    }

    /// @notice Append BYTES from a memory payload; empty payloads are allowed.
    /// @dev Inherits writeBlock's lifecycle and source requirements.
    function writeBytes(
        uint cur,
        bytes memory dst,
        bytes memory data
    ) internal pure returns (bytes memory value, uint nextCur) {
        return writeBlock(cur, dst, Keys.Bytes, data);
    }

    /// @notice Append BYTES from a validated calldata payload cursor; empty payloads are allowed.
    /// @dev Inherits writeBlock's lifecycle and source requirements.
    function writeBytes(
        uint cur,
        bytes memory dst,
        uint dataCur
    ) internal pure returns (bytes memory value, uint nextCur) {
        return writeBlock(cur, dst, Keys.Bytes, dataCur);
    }

    /// @notice Append STRING from a memory payload; empty payloads are allowed.
    /// @dev Inherits writeBlock's lifecycle and source requirements.
    function writeString(
        uint cur,
        bytes memory dst,
        bytes memory data
    ) internal pure returns (bytes memory value, uint nextCur) {
        return writeBlock(cur, dst, Keys.String, data);
    }

    /// @notice Append STRING from a validated calldata payload cursor; empty payloads are allowed.
    /// @dev Inherits writeBlock's lifecycle and source requirements.
    function writeString(
        uint cur,
        bytes memory dst,
        uint dataCur
    ) internal pure returns (bytes memory value, uint nextCur) {
        return writeBlock(cur, dst, Keys.String, dataCur);
    }

    // Composites: Wrap adds child headers around payloads.

    /// @notice Append STEP by copying complete validated calldata BYTES children.
    /// @dev Children include their headers, are not advanced, and are not revalidated.
    function writeStep(
        uint cur,
        bytes memory dst,
        uint cmd,
        uint amount,
        uint inputCur
    ) internal pure returns (bytes memory value, uint nextCur) {
        uint inputSize = length(inputCur);
        uint size = 72 + inputSize;
        uint abs;
        (value, abs, nextCur) = reserve(cur, dst, size);
        unchecked {
            abs = writeHeader(abs, Keys.Step, size - 8);
        }
        abs = write32(abs, bytes32(cmd));
        abs = write32(abs, bytes32(amount));
        copy(abs, uint32(inputCur), inputSize);
    }

    /// @notice Append STEP, wrapping memory payloads in child headers.
    /// @dev Inherits reserve and copy requirements. Sources exclude child headers,
    /// must be disjoint from writes, and are not advanced or revalidated.
    function writeStepWrap(
        uint cur,
        bytes memory dst,
        uint cmd,
        uint amount,
        bytes memory input
    ) internal pure returns (bytes memory value, uint nextCur) {
        uint inputSize = input.length;
        uint size = 80 + inputSize;
        uint abs;
        (value, abs, nextCur) = reserve(cur, dst, size);
        unchecked {
            abs = writeHeader(abs, Keys.Step, size - 8);
        }
        abs = write32(abs, bytes32(cmd));
        abs = write32(abs, bytes32(amount));
        wrap(abs, Keys.Bytes, input, inputSize);
    }

    /// @notice Append STEP, wrapping validated calldata payload cursors in child headers.
    /// @dev Inherits reserve and copy requirements. Sources exclude child headers,
    /// must be disjoint from writes, and are not advanced or revalidated.
    function writeStepWrap(
        uint cur,
        bytes memory dst,
        uint cmd,
        uint amount,
        uint inputCur
    ) internal pure returns (bytes memory value, uint nextCur) {
        uint inputSize = length(inputCur);
        uint size = 80 + inputSize;
        uint abs;
        (value, abs, nextCur) = reserve(cur, dst, size);
        unchecked {
            abs = writeHeader(abs, Keys.Step, size - 8);
        }
        abs = write32(abs, bytes32(cmd));
        abs = write32(abs, bytes32(amount));
        wrap(abs, Keys.Bytes, uint32(inputCur), inputSize);
    }

    /// @notice Append SWAP by copying a complete validated LIST child, including its header.
    /// @dev Inherits reserve/copy requirements. Does not revalidate hops or route semantics.
    function writeSwap(uint cur, bytes memory dst, bytes32 asset, uint amount, uint hopsCur)
        internal pure returns (bytes memory value, uint nextCur)
    {
        uint size = 72 + length(hopsCur);
        uint abs;
        (value, abs, nextCur) = reserve(cur, dst, size);
        abs = writeHeader(abs, Keys.Swap, size - 8);
        abs = write32(abs, asset);
        abs = write32(abs, bytes32(amount));
        copy(abs, uint32(hopsCur), length(hopsCur));
    }

    /// @notice Append SWAP, wrapping memory ASSET blocks in a LIST child.
    /// @dev Inherits reserve/copy requirements; does not validate hops or route semantics.
    function writeSwapWrap(uint cur, bytes memory dst, bytes32 asset, uint amount, bytes memory hops)
        internal pure returns (bytes memory value, uint nextCur)
    {
        uint size = 80 + hops.length;
        uint abs;
        (value, abs, nextCur) = reserve(cur, dst, size);
        abs = writeHeader(abs, Keys.Swap, size - 8);
        abs = write32(abs, asset);
        abs = write32(abs, bytes32(amount));
        wrap(abs, Keys.List, hops, hops.length);
    }

    /// @notice Append SWAP, wrapping a validated ASSET stream cursor in a LIST child.
    /// @dev Sources exclude the LIST header; inherits reserve/copy requirements.
    /// Does not advance the source or revalidate hops or route semantics.
    function writeSwapWrap(uint cur, bytes memory dst, bytes32 asset, uint amount, uint hopsCur)
        internal pure returns (bytes memory value, uint nextCur)
    {
        uint hopsSize = length(hopsCur);
        uint size = 80 + hopsSize;
        uint abs;
        (value, abs, nextCur) = reserve(cur, dst, size);
        abs = writeHeader(abs, Keys.Swap, size - 8);
        abs = write32(abs, asset);
        abs = write32(abs, bytes32(amount));
        wrap(abs, Keys.List, uint32(hopsCur), hopsSize);
    }

    /// @notice Append CALL by copying complete validated calldata BYTES children.
    /// @dev Children include their headers, are not advanced, and are not revalidated.
    function writeCall(
        uint cur,
        bytes memory dst,
        uint target,
        uint value,
        uint payloadCur
    ) internal pure returns (bytes memory output, uint nextCur) {
        uint payloadSize = length(payloadCur);
        uint size = 72 + payloadSize;
        uint abs;
        (output, abs, nextCur) = reserve(cur, dst, size);
        unchecked {
            abs = writeHeader(abs, Keys.Call, size - 8);
        }
        abs = write32(abs, bytes32(target));
        abs = write32(abs, bytes32(value));
        copy(abs, uint32(payloadCur), payloadSize);
    }

    /// @notice Append CALL, wrapping memory payloads in child headers.
    /// @dev Inherits reserve and copy requirements. Sources exclude child headers,
    /// must be disjoint from writes, and are not advanced or revalidated.
    function writeCallWrap(
        uint cur,
        bytes memory dst,
        uint target,
        uint value,
        bytes memory payload
    ) internal pure returns (bytes memory output, uint nextCur) {
        uint payloadSize = payload.length;
        uint size = 80 + payloadSize;
        uint abs;
        (output, abs, nextCur) = reserve(cur, dst, size);
        unchecked {
            abs = writeHeader(abs, Keys.Call, size - 8);
        }
        abs = write32(abs, bytes32(target));
        abs = write32(abs, bytes32(value));
        wrap(abs, Keys.Bytes, payload, payloadSize);
    }

    /// @notice Append CALL, wrapping validated calldata payload cursors in child headers.
    /// @dev Inherits reserve and copy requirements. Sources exclude child headers,
    /// must be disjoint from writes, and are not advanced or revalidated.
    function writeCallWrap(
        uint cur,
        bytes memory dst,
        uint target,
        uint value,
        uint payloadCur
    ) internal pure returns (bytes memory output, uint nextCur) {
        uint payloadSize = length(payloadCur);
        uint size = 80 + payloadSize;
        uint abs;
        (output, abs, nextCur) = reserve(cur, dst, size);
        unchecked {
            abs = writeHeader(abs, Keys.Call, size - 8);
        }
        abs = write32(abs, bytes32(target));
        abs = write32(abs, bytes32(value));
        wrap(abs, Keys.Bytes, uint32(payloadCur), payloadSize);
    }

    /// @notice Append DISPATCH by copying complete validated calldata BYTES children.
    /// @dev Children include their headers, are not advanced, and are not revalidated.
    function writeDispatch(
        uint cur,
        bytes memory dst,
        uint portal,
        uint resources,
        uint payloadCur
    ) internal pure returns (bytes memory value, uint nextCur) {
        uint payloadSize = length(payloadCur);
        uint size = 72 + payloadSize;
        uint abs;
        (value, abs, nextCur) = reserve(cur, dst, size);
        unchecked {
            abs = writeHeader(abs, Keys.Dispatch, size - 8);
        }
        abs = write32(abs, bytes32(portal));
        abs = write32(abs, bytes32(resources));
        copy(abs, uint32(payloadCur), payloadSize);
    }

    /// @notice Append DISPATCH, wrapping memory payloads in child headers.
    /// @dev Inherits reserve and copy requirements. Sources exclude child headers,
    /// must be disjoint from writes, and are not advanced or revalidated.
    function writeDispatchWrap(
        uint cur,
        bytes memory dst,
        uint portal,
        uint resources,
        bytes memory payload
    ) internal pure returns (bytes memory value, uint nextCur) {
        uint payloadSize = payload.length;
        uint size = 80 + payloadSize;
        uint abs;
        (value, abs, nextCur) = reserve(cur, dst, size);
        unchecked {
            abs = writeHeader(abs, Keys.Dispatch, size - 8);
        }
        abs = write32(abs, bytes32(portal));
        abs = write32(abs, bytes32(resources));
        wrap(abs, Keys.Bytes, payload, payloadSize);
    }

    /// @notice Append DISPATCH, wrapping validated calldata payload cursors in child headers.
    /// @dev Inherits reserve and copy requirements. Sources exclude child headers,
    /// must be disjoint from writes, and are not advanced or revalidated.
    function writeDispatchWrap(
        uint cur,
        bytes memory dst,
        uint portal,
        uint resources,
        uint payloadCur
    ) internal pure returns (bytes memory value, uint nextCur) {
        uint payloadSize = length(payloadCur);
        uint size = 80 + payloadSize;
        uint abs;
        (value, abs, nextCur) = reserve(cur, dst, size);
        unchecked {
            abs = writeHeader(abs, Keys.Dispatch, size - 8);
        }
        abs = write32(abs, bytes32(portal));
        abs = write32(abs, bytes32(resources));
        wrap(abs, Keys.Bytes, uint32(payloadCur), payloadSize);
    }

    /// @notice Append RELAY by copying complete validated calldata BYTES children.
    /// @dev Children include their headers, are not advanced, and are not revalidated.
    function writeRelay(
        uint cur,
        bytes memory dst,
        uint inputCur,
        uint stepsCur
    ) internal pure returns (bytes memory value, uint nextCur) {
        uint inputSize = length(inputCur);
        uint stepsSize = length(stepsCur);
        uint size = 8 + inputSize + stepsSize;
        uint abs;
        (value, abs, nextCur) = reserve(cur, dst, size);
        unchecked {
            abs = writeHeader(abs, Keys.Relay, size - 8);
        }
        abs = copy(abs, uint32(inputCur), inputSize);
        copy(abs, uint32(stepsCur), stepsSize);
    }

    /// @notice Append RELAY, wrapping memory payloads in child headers.
    /// @dev Inherits reserve and copy requirements. Sources exclude child headers,
    /// must be disjoint from writes, and are not advanced or revalidated.
    function writeRelayWrap(
        uint cur,
        bytes memory dst,
        bytes memory input,
        bytes memory steps
    ) internal pure returns (bytes memory value, uint nextCur) {
        uint inputSize = input.length;
        uint stepsSize = steps.length;
        uint size = 24 + inputSize + stepsSize;
        uint abs;
        (value, abs, nextCur) = reserve(cur, dst, size);
        unchecked {
            abs = writeHeader(abs, Keys.Relay, size - 8);
        }
        abs = wrap(abs, Keys.Bytes, input, inputSize);
        wrap(abs, Keys.Bytes, steps, stepsSize);
    }

    /// @notice Append RELAY, wrapping validated calldata payload cursors in child headers.
    /// @dev Inherits reserve and copy requirements. Sources exclude child headers,
    /// must be disjoint from writes, and are not advanced or revalidated.
    function writeRelayWrap(
        uint cur,
        bytes memory dst,
        uint inputCur,
        uint stepsCur
    ) internal pure returns (bytes memory value, uint nextCur) {
        uint inputSize = length(inputCur);
        uint stepsSize = length(stepsCur);
        uint size = 24 + inputSize + stepsSize;
        uint abs;
        (value, abs, nextCur) = reserve(cur, dst, size);
        unchecked {
            abs = writeHeader(abs, Keys.Relay, size - 8);
        }
        abs = wrap(abs, Keys.Bytes, uint32(inputCur), inputSize);
        wrap(abs, Keys.Bytes, uint32(stepsCur), stepsSize);
    }

    /// @notice Append RECOVER by copying complete validated calldata BYTES children.
    /// @dev Children include their headers, are not advanced, and are not revalidated.
    function writeRecover(
        uint cur,
        bytes memory dst,
        uint handler,
        uint value,
        bytes32 recoverykey,
        uint witnessCur
    ) internal pure returns (bytes memory output, uint nextCur) {
        uint witnessSize = length(witnessCur);
        uint size = 104 + witnessSize;
        uint abs;
        (output, abs, nextCur) = reserve(cur, dst, size);
        unchecked {
            abs = writeHeader(abs, Keys.Recover, size - 8);
        }
        abs = write32(abs, bytes32(handler));
        abs = write32(abs, bytes32(value));
        abs = write32(abs, recoverykey);
        copy(abs, uint32(witnessCur), witnessSize);
    }

    /// @notice Append RECOVER, wrapping memory payloads in child headers.
    /// @dev Inherits reserve and copy requirements. Sources exclude child headers,
    /// must be disjoint from writes, and are not advanced or revalidated.
    function writeRecoverWrap(
        uint cur,
        bytes memory dst,
        uint handler,
        uint value,
        bytes32 recoverykey,
        bytes memory witness
    ) internal pure returns (bytes memory output, uint nextCur) {
        uint witnessSize = witness.length;
        uint size = 112 + witnessSize;
        uint abs;
        (output, abs, nextCur) = reserve(cur, dst, size);
        unchecked {
            abs = writeHeader(abs, Keys.Recover, size - 8);
        }
        abs = write32(abs, bytes32(handler));
        abs = write32(abs, bytes32(value));
        abs = write32(abs, recoverykey);
        wrap(abs, Keys.Bytes, witness, witnessSize);
    }

    /// @notice Append RECOVER, wrapping validated calldata payload cursors in child headers.
    /// @dev Inherits reserve and copy requirements. Sources exclude child headers,
    /// must be disjoint from writes, and are not advanced or revalidated.
    function writeRecoverWrap(
        uint cur,
        bytes memory dst,
        uint handler,
        uint value,
        bytes32 recoverykey,
        uint witnessCur
    ) internal pure returns (bytes memory output, uint nextCur) {
        uint witnessSize = length(witnessCur);
        uint size = 112 + witnessSize;
        uint abs;
        (output, abs, nextCur) = reserve(cur, dst, size);
        unchecked {
            abs = writeHeader(abs, Keys.Recover, size - 8);
        }
        abs = write32(abs, bytes32(handler));
        abs = write32(abs, bytes32(value));
        abs = write32(abs, recoverykey);
        wrap(abs, Keys.Bytes, uint32(witnessCur), witnessSize);
    }

    /// @notice Append LABEL by copying complete validated calldata STRING children.
    /// @dev Children include their headers, are not advanced, and are not revalidated.
    function writeLabel(
        uint cur,
        bytes memory dst,
        bytes32 namespace,
        uint nameCur
    ) internal pure returns (bytes memory value, uint nextCur) {
        uint nameSize = length(nameCur);
        uint size = 40 + nameSize;
        uint abs;
        (value, abs, nextCur) = reserve(cur, dst, size);
        unchecked {
            abs = writeHeader(abs, Keys.Label, size - 8);
        }
        abs = write32(abs, namespace);
        copy(abs, uint32(nameCur), nameSize);
    }

    /// @notice Append LABEL, wrapping memory payloads in child headers.
    /// @dev Inherits reserve and copy requirements. Sources exclude child headers,
    /// must be disjoint from writes, and are not advanced or revalidated.
    function writeLabelWrap(
        uint cur,
        bytes memory dst,
        bytes32 namespace,
        bytes memory name
    ) internal pure returns (bytes memory value, uint nextCur) {
        uint nameSize = name.length;
        uint size = 48 + nameSize;
        uint abs;
        (value, abs, nextCur) = reserve(cur, dst, size);
        unchecked {
            abs = writeHeader(abs, Keys.Label, size - 8);
        }
        abs = write32(abs, namespace);
        wrap(abs, Keys.String, name, nameSize);
    }

    /// @notice Append LABEL, wrapping validated calldata payload cursors in child headers.
    /// @dev Inherits reserve and copy requirements. Sources exclude child headers,
    /// must be disjoint from writes, and are not advanced or revalidated.
    function writeLabelWrap(
        uint cur,
        bytes memory dst,
        bytes32 namespace,
        uint nameCur
    ) internal pure returns (bytes memory value, uint nextCur) {
        uint nameSize = length(nameCur);
        uint size = 48 + nameSize;
        uint abs;
        (value, abs, nextCur) = reserve(cur, dst, size);
        unchecked {
            abs = writeHeader(abs, Keys.Label, size - 8);
        }
        abs = write32(abs, namespace);
        wrap(abs, Keys.String, uint32(nameCur), nameSize);
    }

    /// @notice Append SCHEMA by copying complete validated calldata STRING children.
    /// @dev Children include their headers, are not advanced, and are not revalidated.
    function writeSchema(
        uint cur,
        bytes memory dst,
        uint spec,
        uint bodyCur
    ) internal pure returns (bytes memory value, uint nextCur) {
        uint bodySize = length(bodyCur);
        uint size = 40 + bodySize;
        uint abs;
        (value, abs, nextCur) = reserve(cur, dst, size);
        unchecked {
            abs = writeHeader(abs, Keys.Schema, size - 8);
        }
        abs = write32(abs, bytes32(spec));
        copy(abs, uint32(bodyCur), bodySize);
    }

    /// @notice Append SCHEMA, wrapping memory payloads in child headers.
    /// @dev Inherits reserve and copy requirements. Sources exclude child headers,
    /// must be disjoint from writes, and are not advanced or revalidated.
    function writeSchemaWrap(
        uint cur,
        bytes memory dst,
        uint spec,
        bytes memory body
    ) internal pure returns (bytes memory value, uint nextCur) {
        uint bodySize = body.length;
        uint size = 48 + bodySize;
        uint abs;
        (value, abs, nextCur) = reserve(cur, dst, size);
        unchecked {
            abs = writeHeader(abs, Keys.Schema, size - 8);
        }
        abs = write32(abs, bytes32(spec));
        wrap(abs, Keys.String, body, bodySize);
    }

    /// @notice Append SCHEMA, wrapping validated calldata payload cursors in child headers.
    /// @dev Inherits reserve and copy requirements. Sources exclude child headers,
    /// must be disjoint from writes, and are not advanced or revalidated.
    function writeSchemaWrap(
        uint cur,
        bytes memory dst,
        uint spec,
        uint bodyCur
    ) internal pure returns (bytes memory value, uint nextCur) {
        uint bodySize = length(bodyCur);
        uint size = 48 + bodySize;
        uint abs;
        (value, abs, nextCur) = reserve(cur, dst, size);
        unchecked {
            abs = writeHeader(abs, Keys.Schema, size - 8);
        }
        abs = write32(abs, bytes32(spec));
        wrap(abs, Keys.String, uint32(bodyCur), bodySize);
    }

    /// @notice Append CONTEXT by copying complete validated memory BYTES children.
    /// @dev Inherits reserve's lifecycle requirements. Children must be validated
    /// complete BYTES blocks, disjoint from destination writes.
    function writeContext(
        uint cur,
        bytes memory dst,
        bytes32 account,
        bytes memory state,
        bytes memory input
    ) internal pure returns (bytes memory value, uint nextCur) {
        uint stateSize = state.length;
        uint inputSize = input.length;
        uint size = 40 + stateSize + inputSize;
        uint abs;
        (value, abs, nextCur) = reserve(cur, dst, size);
        unchecked {
            abs = writeHeader(abs, Keys.Context, size - 8);
        }
        abs = write32(abs, account);
        abs = copy(abs, state, stateSize);
        copy(abs, input, inputSize);
    }

    /// @notice Append CONTEXT by copying complete validated calldata BYTES children.
    /// @dev Inherits reserve's lifecycle requirements. Children must be validated
    /// complete BYTES blocks, disjoint from destination writes.
    function writeContext(
        uint cur,
        bytes memory dst,
        bytes32 account,
        uint stateCur,
        uint inputCur
    ) internal pure returns (bytes memory value, uint nextCur) {
        uint stateSize = length(stateCur);
        uint inputSize = length(inputCur);
        uint size = 40 + stateSize + inputSize;
        uint abs;
        (value, abs, nextCur) = reserve(cur, dst, size);
        unchecked {
            abs = writeHeader(abs, Keys.Context, size - 8);
        }
        abs = write32(abs, account);
        abs = copy(abs, uint32(stateCur), stateSize);
        copy(abs, uint32(inputCur), inputSize);
    }

    /// @notice Append CONTEXT by wrapping memory payloads in BYTES headers.
    /// @dev Inherits reserve's lifecycle requirements. Payload ranges must be valid
    /// and disjoint from destination writes.
    function writeContextWrap(
        uint cur,
        bytes memory dst,
        bytes32 account,
        bytes memory state,
        bytes memory input
    ) internal pure returns (bytes memory value, uint nextCur) {
        uint stateSize = state.length;
        uint inputSize = input.length;
        uint size = 56 + stateSize + inputSize;
        uint abs;
        (value, abs, nextCur) = reserve(cur, dst, size);
        unchecked {
            abs = writeHeader(abs, Keys.Context, size - 8);
        }
        abs = write32(abs, account);
        abs = wrap(abs, Keys.Bytes, state, stateSize);
        wrap(abs, Keys.Bytes, input, inputSize);
    }

    /// @notice Append CONTEXT by wrapping validated calldata payload cursors.
    /// @dev Inherits reserve's lifecycle requirements. Payload ranges must be valid
    /// and disjoint from destination writes.
    function writeContextWrap(
        uint cur,
        bytes memory dst,
        bytes32 account,
        uint stateCur,
        uint inputCur
    ) internal pure returns (bytes memory value, uint nextCur) {
        uint stateSize = length(stateCur);
        uint inputSize = length(inputCur);
        uint size = 56 + stateSize + inputSize;
        uint abs;
        (value, abs, nextCur) = reserve(cur, dst, size);
        unchecked {
            abs = writeHeader(abs, Keys.Context, size - 8);
        }
        abs = write32(abs, account);
        abs = wrap(abs, Keys.Bytes, uint32(stateCur), stateSize);
        wrap(abs, Keys.Bytes, uint32(inputCur), inputSize);
    }

    // Creators: fixed-size blocks, payload blocks, then composites.

    /// @notice Create a complete ACCOUNT block with zero allocation padding.
    /// @dev Preserves field order and full-width values; performs no semantic validation.
    function createAccount(bytes32 account) internal pure returns (bytes memory value) {
        value = allocate(40);
        uint abs = writeHeader(pos(value, 0), Keys.Account, 32);
        write32(abs, account);
    }

    /// @notice Create a complete ASSET block with zero allocation padding.
    /// @dev Preserves field order and full-width values; performs no semantic validation.
    function createAsset(bytes32 asset) internal pure returns (bytes memory value) {
        value = allocate(40);
        uint abs = writeHeader(pos(value, 0), Keys.Asset, 32);
        write32(abs, asset);
    }

    /// @notice Create a complete NODE block with zero allocation padding.
    /// @dev Preserves field order and full-width values; performs no semantic validation.
    function createNode(uint node) internal pure returns (bytes memory value) {
        value = allocate(40);
        uint abs = writeHeader(pos(value, 0), Keys.Node, 32);
        write32(abs, bytes32(node));
    }

    /// @notice Create a complete ENTITY block with zero allocation padding.
    /// @dev Preserves field order and full-width values; performs no semantic validation.
    function createEntity(uint entity) internal pure returns (bytes memory value) {
        value = allocate(40);
        uint abs = writeHeader(pos(value, 0), Keys.Entity, 32);
        write32(abs, bytes32(entity));
    }

    /// @notice Create a complete STATUS block with zero allocation padding.
    /// @dev Preserves field order and full-width values; performs no semantic validation.
    function createStatus(uint code) internal pure returns (bytes memory value) {
        value = allocate(40);
        uint abs = writeHeader(pos(value, 0), Keys.Status, 32);
        write32(abs, bytes32(code));
    }

    /// @notice Create a CODES block containing packed identifiers.
    /// @dev Preserves all bits with zero allocation padding; performs no semantic validation.
    function createCodes(uint codes) internal pure returns (bytes memory value) {
        value = allocate(40);
        uint abs = writeHeader(pos(value, 0), Keys.Codes, 32);
        write32(abs, bytes32(codes));
    }

    /// @notice Create a complete LIMITS block with zero allocation padding.
    /// @dev Preserves field order and full-width values; performs no semantic validation.
    function createLimits(uint limits) internal pure returns (bytes memory value) {
        value = allocate(40);
        uint abs = writeHeader(pos(value, 0), Keys.Limits, 32);
        write32(abs, bytes32(limits));
    }

    /// @notice Create an ACTION annotation from a full-width action identifier.
    /// @param actionid Canonical action identifier, encoded unchanged.
    /// @return value Complete 40-byte ACTION block with zero allocation padding.
    function createAction(uint actionid) internal pure returns (bytes memory value) {
        value = allocate(40);
        uint abs = writeHeader(pos(value, 0), Keys.Action, 32);
        write32(abs, bytes32(actionid));
    }

    /// @notice Create a COUNTERPARTY annotation from an account identifier.
    /// @param account Counterparty account ID, or zero for Rootzero.
    /// @return value Complete 40-byte COUNTERPARTY block with zero allocation padding.
    function createCounterparty(bytes32 account) internal pure returns (bytes memory value) {
        value = allocate(40);
        uint abs = writeHeader(pos(value, 0), Keys.Counterparty, 32);
        write32(abs, account);
    }

    /// @notice Create a complete AMOUNT block with zero allocation padding.
    /// @dev Preserves field order and full-width values; performs no semantic validation.
    function createAmount(bytes32 asset, uint amount) internal pure returns (bytes memory value) {
        value = allocate(72);
        uint abs = writeHeader(pos(value, 0), Keys.Amount, 64);
        abs = write32(abs, asset);
        write32(abs, bytes32(amount));
    }

    /// @notice Create a complete 72-byte BALANCE block with zero allocation padding.
    /// @param asset Asset identifier, encoded unchanged.
    /// @param amount Full-width balance amount, encoded unchanged.
    /// @return value Complete BALANCE block in memory.
    function createBalance(bytes32 asset, uint amount) internal pure returns (bytes memory value) {
        value = allocate(72);
        uint abs = writeHeader(pos(value, 0), Keys.Balance, 64);
        abs = write32(abs, asset);
        write32(abs, bytes32(amount));
    }

    /// @notice Create an EXECUTION_COST annotation with base and per-batch costs.
    /// @param base Fixed execution cost per invocation.
    /// @param batch Additional execution cost per logical batch.
    /// @return value Complete encoded annotation with zero allocation padding.
    function createExecutionCost(uint base, uint batch) internal pure returns (bytes memory value) {
        value = allocate(72);
        uint abs = writeHeader(pos(value, 0), Keys.ExecutionCost, 64);
        abs = write32(abs, bytes32(base));
        write32(abs, bytes32(batch));
    }

    /// @notice Create a complete ASSETLIABILITY block with zero allocation padding.
    /// @dev Preserves field order and full-width values; performs no semantic validation.
    function createAssetLiability(bytes32 asset, bytes32 liability) internal pure returns (bytes memory value) {
        value = allocate(72);
        uint abs = writeHeader(pos(value, 0), Keys.AssetLiability, 64);
        abs = write32(abs, asset);
        write32(abs, liability);
    }

    /// @notice Create a complete ACCOUNTASSET block with zero allocation padding.
    /// @dev Preserves field order and full-width values; performs no semantic validation.
    function createAccountAsset(bytes32 account, bytes32 asset) internal pure returns (bytes memory value) {
        value = allocate(72);
        uint abs = writeHeader(pos(value, 0), Keys.AccountAsset, 64);
        abs = write32(abs, account);
        write32(abs, asset);
    }

    /// @notice Create a complete HOSTASSET block with zero allocation padding.
    /// @dev Preserves field order and full-width values; performs no semantic validation.
    function createHostAsset(uint host, bytes32 asset) internal pure returns (bytes memory value) {
        value = allocate(72);
        uint abs = writeHeader(pos(value, 0), Keys.HostAsset, 64);
        abs = write32(abs, bytes32(host));
        write32(abs, asset);
    }

    /// @notice Create a complete BOOTSTRAP block with zero allocation padding.
    /// @dev Preserves field order and full-width values; performs no semantic validation.
    function createBootstrap(bytes32 asset, uint amount, uint budget) internal pure returns (bytes memory value) {
        value = allocate(104);
        uint abs = writeHeader(pos(value, 0), Keys.Bootstrap, 96);
        abs = write32(abs, asset);
        abs = write32(abs, bytes32(amount));
        write32(abs, bytes32(budget));
    }

    /// @notice Create a complete ALLOCATION block with zero allocation padding.
    /// @dev Preserves field order and full-width values; performs no semantic validation.
    function createAllocation(uint host, bytes32 asset, uint amount) internal pure returns (bytes memory value) {
        value = allocate(104);
        uint abs = writeHeader(pos(value, 0), Keys.Allocation, 96);
        abs = write32(abs, bytes32(host));
        abs = write32(abs, asset);
        write32(abs, bytes32(amount));
    }

    /// @notice Create a complete ALLOWANCE block with zero allocation padding.
    /// @dev Preserves field order and full-width values; performs no semantic validation.
    function createAllowance(uint host, bytes32 asset, uint amount) internal pure returns (bytes memory value) {
        value = allocate(104);
        uint abs = writeHeader(pos(value, 0), Keys.Allowance, 96);
        abs = write32(abs, bytes32(host));
        abs = write32(abs, asset);
        write32(abs, bytes32(amount));
    }

    /// @notice Create a complete CUSTODY block with zero allocation padding.
    /// @dev Preserves field order and full-width values; performs no semantic validation.
    function createCustody(uint host, bytes32 asset, uint amount) internal pure returns (bytes memory value) {
        value = allocate(104);
        uint abs = writeHeader(pos(value, 0), Keys.Custody, 96);
        abs = write32(abs, bytes32(host));
        abs = write32(abs, asset);
        write32(abs, bytes32(amount));
    }

    /// @notice Create a complete ACCOUNTAMOUNT block with zero allocation padding.
    /// @dev Preserves field order and full-width values; performs no semantic validation.
    function createAccountAmount(bytes32 account, bytes32 asset, uint amount) internal pure returns (bytes memory value) {
        value = allocate(104);
        uint abs = writeHeader(pos(value, 0), Keys.AccountAmount, 96);
        abs = write32(abs, account);
        abs = write32(abs, asset);
        write32(abs, bytes32(amount));
    }

    /// @notice Create a complete HOSTAMOUNT block with zero allocation padding.
    /// @dev Preserves field order and full-width values; performs no semantic validation.
    function createHostAmount(uint host, bytes32 asset, uint amount) internal pure returns (bytes memory value) {
        value = allocate(104);
        uint abs = writeHeader(pos(value, 0), Keys.HostAmount, 96);
        abs = write32(abs, bytes32(host));
        abs = write32(abs, asset);
        write32(abs, bytes32(amount));
    }

    /// @notice Create a complete HOSTACCOUNTASSET block with zero allocation padding.
    /// @dev Preserves field order and full-width values; performs no semantic validation.
    function createHostAccountAsset(uint host, bytes32 account, bytes32 asset) internal pure returns (bytes memory value) {
        value = allocate(104);
        uint abs = writeHeader(pos(value, 0), Keys.HostAccountAsset, 96);
        abs = write32(abs, bytes32(host));
        abs = write32(abs, account);
        write32(abs, asset);
    }

    /// @notice Create a complete QUOTE block with zero allocation padding.
    /// @dev Preserves field order and full-width values; performs no semantic validation.
    function createQuote(bytes32 asset, uint amount, bytes32 liability, uint debt) internal pure returns (bytes memory value) {
        value = allocate(136);
        uint abs = writeHeader(pos(value, 0), Keys.Quote, 128);
        abs = write32(abs, asset);
        abs = write32(abs, bytes32(amount));
        abs = write32(abs, liability);
        write32(abs, bytes32(debt));
    }

    /// @notice Create a complete TRANSACTION block with zero allocation padding.
    /// @dev Preserves field order and full-width values; performs no semantic validation.
    function createTransaction(bytes32 from, bytes32 to, bytes32 asset, uint amount) internal pure returns (bytes memory value) {
        value = allocate(136);
        uint abs = writeHeader(pos(value, 0), Keys.Transaction, 128);
        abs = write32(abs, from);
        abs = write32(abs, to);
        abs = write32(abs, asset);
        write32(abs, bytes32(amount));
    }

    /// @notice Create a complete HOSTACCOUNTAMOUNT block with zero allocation padding.
    /// @dev Preserves field order and full-width values; performs no semantic validation.
    function createHostAccountAmount(uint host, bytes32 account, bytes32 asset, uint amount) internal pure returns (bytes memory value) {
        value = allocate(136);
        uint abs = writeHeader(pos(value, 0), Keys.HostAccountAmount, 128);
        abs = write32(abs, bytes32(host));
        abs = write32(abs, account);
        abs = write32(abs, asset);
        write32(abs, bytes32(amount));
    }

    /// @notice Create a complete POSITION block with zero allocation padding.
    /// @dev Preserves field order and full-width values; performs no semantic validation.
    function createPosition(bytes32 asset, uint amount, bytes32 liability, uint debt, bytes32 counterparty) internal pure returns (bytes memory value) {
        value = allocate(168);
        uint abs = writeHeader(pos(value, 0), Keys.Position, 160);
        abs = write32(abs, asset);
        abs = write32(abs, bytes32(amount));
        abs = write32(abs, liability);
        abs = write32(abs, bytes32(debt));
        write32(abs, counterparty);
    }

    // Payload creators: generic key followed by named wrappers.

    /// @notice Create a block by wrapping a memory payload in the supplied key's header.
    /// @dev Checks total size fits uint32. Does not validate schema or payload contents.
    function createBlock(bytes4 key, bytes memory data) internal pure returns (bytes memory value) {
        uint size = data.length;
        value = allocate(8 + size);
        wrap(pos(value, 0), key, data, size);
    }

    /// @notice Create a block by wrapping a validated calldata payload cursor.
    /// @dev Requires current <= end <= calldatasize; ignores metadata and preserves
    /// the cursor. Checks total size fits uint32; does not validate payload contents.
    function createBlock(bytes4 key, uint dataCur) internal pure returns (bytes memory value) {
        uint size = length(dataCur);
        value = allocate(8 + size);
        wrap(pos(value, 0), key, uint32(dataCur), size);
    }

    /// @notice Create LIST by wrapping a memory payload; may be empty.
    /// @dev Inherits createBlock's size and source requirements. Input excludes the header.
    function createList(bytes memory data) internal pure returns (bytes memory value) {
        return createBlock(Keys.List, data);
    }

    /// @notice Create LIST by wrapping a validated calldata payload cursor; may be empty.
    /// @dev Inherits createBlock's size and source requirements. Input excludes the header.
    function createList(uint dataCur) internal pure returns (bytes memory value) {
        return createBlock(Keys.List, dataCur);
    }

    /// @notice Create BYTES by wrapping a memory payload; may be empty.
    /// @dev Inherits createBlock's size and source requirements. Input excludes the header.
    function createBytes(bytes memory data) internal pure returns (bytes memory value) {
        return createBlock(Keys.Bytes, data);
    }

    /// @notice Create BYTES by wrapping a validated calldata payload cursor; may be empty.
    /// @dev Inherits createBlock's size and source requirements. Input excludes the header.
    function createBytes(uint dataCur) internal pure returns (bytes memory value) {
        return createBlock(Keys.Bytes, dataCur);
    }

    /// @notice Create STRING by wrapping a memory payload; may be empty.
    /// @dev Inherits createBlock's size and source requirements. Input excludes the header.
    function createString(bytes memory data) internal pure returns (bytes memory value) {
        return createBlock(Keys.String, data);
    }

    /// @notice Create STRING by wrapping a validated calldata payload cursor; may be empty.
    /// @dev Inherits createBlock's size and source requirements. Input excludes the header.
    function createString(uint dataCur) internal pure returns (bytes memory value) {
        return createBlock(Keys.String, dataCur);
    }

    // Composite creators: values and payloads, with child headers constructed here.

    /// @notice Encode a CONTEXT by wrapping memory-backed state and input in BYTES headers.
    /// @dev Copies each stream directly to its final destination with MCOPY.
    /// Checks total size, but does not validate the nested stream contents.
    /// @param account Account identifier to encode.
    /// @param state Encoded state stream in memory; may be empty.
    /// @param input Encoded input stream in memory; may be empty.
    /// @return value Complete encoded CONTEXT block in memory.
    function createContext(
        bytes32 account,
        bytes memory state,
        bytes memory input
    ) internal pure returns (bytes memory value) {
        uint stateSize = state.length;
        uint inputSize = input.length;
        uint size = 56 + stateSize + inputSize;
        value = allocate(size);
        uint abs = pos(value, 0);
        unchecked {
            abs = writeHeader(abs, Keys.Context, size - 8);
            abs = write32(abs, account);
            abs = wrap(abs, Keys.Bytes, state, stateSize);
            wrap(abs, Keys.Bytes, input, inputSize);
        }
    }

    /// @notice Encode a CONTEXT by wrapping calldata-backed state and input in BYTES headers.
    /// @dev Requires current <= end <= calldatasize for each cursor. Copies only
    /// their remaining ranges directly into the final output with CALLDATACOPY.
    /// No intermediate buffers, repeated bounds checks, or cursor advancement.
    /// Ignores metadata and does not skip headers or validate stream contents.
    /// The complete output size must fit uint32.
    /// @param account Account identifier to encode.
    /// @param stateCur Validated cursor over the encoded state stream.
    /// @param inputCur Validated cursor over the encoded input stream.
    /// @return value Complete encoded CONTEXT block in memory.
    function createContext(
        bytes32 account,
        uint stateCur,
        uint inputCur
    ) internal pure returns (bytes memory value) {
        uint stateSize = length(stateCur);
        uint inputSize = length(inputCur);
        uint size = 56 + stateSize + inputSize;
        value = allocate(size);
        uint abs = pos(value, 0);
        unchecked {
            abs = writeHeader(abs, Keys.Context, size - 8);
            abs = write32(abs, account);
            abs = wrap(abs, Keys.Bytes, uint32(stateCur), stateSize);
            wrap(abs, Keys.Bytes, uint32(inputCur), inputSize);
        }
    }
    /// @notice Create LABEL by wrapping a memory payload in a STRING child header.
    /// @param namespace Label namespace.
    /// @param name Raw text bytes, excluding the STRING header.
    /// @return value Complete LABEL block with zero allocation padding.
    function createLabel(bytes32 namespace, bytes memory name) internal pure returns (bytes memory value) {
        uint size = 48 + name.length;
        value = allocate(size);
        unchecked {
            uint abs = writeHeader(pos(value, 0), Keys.Label, size - 8);
            abs = write32(abs, namespace);
            wrap(abs, Keys.String, name, name.length);
        }
    }

    /// @notice Create SCHEMA by wrapping a memory payload in a STRING child header.
    /// @param spec Packed block specification, encoded unchanged.
    /// @param body Raw schema text bytes, excluding the STRING header.
    /// @return value Complete SCHEMA block with zero allocation padding.
    function createSchema(uint spec, bytes memory body) internal pure returns (bytes memory value) {
        uint size = 48 + body.length;
        value = allocate(size);
        unchecked {
            uint abs = writeHeader(pos(value, 0), Keys.Schema, size - 8);
            abs = write32(abs, bytes32(spec));
            wrap(abs, Keys.String, body, body.length);
        }
    }

    /// @notice Create GROUPS by wrapping a memory payload in a STRING child header.
    /// @dev Allocates only the final block; no intermediate STRING buffer.
    /// @param description Raw description bytes, excluding the STRING header.
    /// @return value Complete GROUPS block with zero allocation padding.
    function createGroups(bytes memory description) internal pure returns (bytes memory value) {
        uint size = 16 + description.length;
        value = allocate(size);
        unchecked {
            uint abs = writeHeader(pos(value, 0), Keys.Groups, size - 8);
            wrap(abs, Keys.String, description, description.length);
        }
    }
}
