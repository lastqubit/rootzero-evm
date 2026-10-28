// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

import {AssetAmount, Position, Booking} from "../core/Types.sol";
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

    /// @notice Allocate an uninitialized uint32-sized result with zero padding.
    /// @dev Use pos(value, 0) for the first write position. Fill all logical bytes before
    /// exposing the result. Only the rounded final allocation is retained: writes
    /// may interleave allocations if they stay inside that owned extent. Any
    /// scratch beyond it must be used before further allocations.
    /// @param size Logical output length to allocate, in bytes.
    /// @return value Allocated output; logical bytes must be initialized before use.
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

    /// @notice Return the unchecked absolute memory address at byte offset i in dst.
    /// @dev The caller must reserve sufficient memory before writing at this position.
    /// @param dst Destination memory buffer.
    /// @param i Byte offset from the start of the memory payload.
    /// @return abs Absolute memory address at the requested payload offset.
    function pos(bytes memory dst, uint i) internal pure returns (uint abs) {
        assembly ("memory-safe") {
            abs := add(add(dst, 32), i)
        }
    }

    /// @notice Remaining length of a validated calldata cursor; ignores metadata.
    /// @param cur Packed source cursor containing the current position and exclusive end.
    /// @return size Remaining source length, in bytes.
    function length(uint cur) internal pure returns (uint size) {
        uint abs = uint32(cur);
        unchecked {
            size = uint32(cur >> 32) - abs;
        }
    }

    /// @notice Write a header and return its payload position.
    /// @dev Requires size <= uint32.max.
    /// Also overwrites the next 24 bytes: reserve them or use temporary free memory
    /// immediately after a fresh result. Pointer arithmetic is unchecked.
    /// @param abs Absolute memory byte position; not a packed cursor.
    /// @param key Block key.
    /// @param size Payload length, in bytes.
    /// @return nextAbs Absolute memory position of the block payload.
    function writeHeader(uint abs, bytes4 key, uint size) internal pure returns (uint nextAbs) {
        uint keyWord = uint32(key);
        assembly ("memory-safe") {
            mstore(abs, or(shl(224, keyWord), shl(192, size)))
            nextAbs := add(abs, 8)
        }
    }

    /// @notice Write a word to reserved memory and return the position after it.
    /// @param abs Absolute memory byte position; not a packed cursor.
    /// @param value Full-width value to encode or transform.
    /// @return nextAbs Absolute memory position immediately after the written bytes.
    function write32(uint abs, bytes32 value) internal pure returns (uint nextAbs) {
        assembly ("memory-safe") {
            mstore(abs, value)
            nextAbs := add(abs, 32)
        }
    }

    /// @notice Copy a memory range and return the next destination.
    /// @dev Source and destination
    /// must be valid; composite callers must keep sources disjoint from all writes.
    /// @param abs Absolute memory byte position; not a packed cursor.
    /// @param source Memory source bytes.
    /// @param size Number of source bytes to copy.
    /// @return nextAbs Absolute memory position immediately after the written bytes.
    function copy(uint abs, bytes memory source, uint size) internal pure returns (uint nextAbs) {
        assembly ("memory-safe") {
            mcopy(abs, add(source, 32), size)
            nextAbs := add(abs, size)
        }
    }

    /// @notice Copy a validated absolute calldata range to reserved memory and advance.
    /// @param abs Absolute memory byte position; not a packed cursor.
    /// @param sourceAbs Absolute calldata byte position of the source.
    /// @param size Number of source bytes to copy.
    /// @return nextAbs Absolute memory position immediately after the written bytes.
    function copy(uint abs, uint sourceAbs, uint size) internal pure returns (uint nextAbs) {
        assembly ("memory-safe") {
            calldatacopy(abs, sourceAbs, size)
            nextAbs := add(abs, size)
        }
    }

    /// @notice Copy all source bytes unchanged, including any existing block header.
    /// @param abs Absolute memory byte position; not a packed cursor.
    /// @param source Memory source bytes.
    /// @return nextAbs Absolute memory position immediately after the written bytes.
    function copy(uint abs, bytes memory source) internal pure returns (uint nextAbs) {
        return copy(abs, source, source.length);
    }

    /// @notice Copy a validated cursor's remaining range unchanged and advance destination.
    /// @param abs Absolute memory byte position; not a packed cursor.
    /// @param cur Packed source cursor containing the current position and exclusive end.
    /// @return nextAbs Absolute memory position immediately after the written bytes.
    function copy(uint abs, uint cur) internal pure returns (uint nextAbs) {
        return copy(abs, uint32(cur), length(cur));
    }

    /// @notice Wrap size memory bytes with a header and advance past the whole block.
    /// @dev Requires size <= payload.length and size <= uint32.max; inherits header
    /// scratch and copy preconditions. Use when the caller already knows the size.
    /// @param abs Absolute memory byte position; not a packed cursor.
    /// @param key Block key.
    /// @param payload Memory payload bytes, excluding the new block header.
    /// @param size Number of source bytes to copy.
    /// @return nextAbs Absolute memory position immediately after the written bytes.
    function wrap(uint abs, bytes4 key, bytes memory payload, uint size) internal pure returns (uint nextAbs) {
        return copy(writeHeader(abs, key, size), payload, size);
    }

    /// @notice Wrap a validated absolute calldata range and advance past the block.
    /// @dev Requires size <= uint32.max; inherits header scratch and copy preconditions.
    /// @param abs Absolute memory byte position; not a packed cursor.
    /// @param key Block key.
    /// @param sourceAbs Absolute calldata byte position of the source.
    /// @param size Number of source bytes to copy.
    /// @return nextAbs Absolute memory position immediately after the written bytes.
    function wrap(uint abs, bytes4 key, uint sourceAbs, uint size) internal pure returns (uint nextAbs) {
        return copy(writeHeader(abs, key, size), sourceAbs, size);
    }

    /// @notice Wrap a memory payload with a new header and advance past the whole block.
    /// @dev Inherits writeHeader scratch requirements and copy source/destination preconditions.
    /// @param abs Absolute memory byte position; not a packed cursor.
    /// @param key Block key.
    /// @param payload Memory payload bytes, excluding the new block header.
    /// @return nextAbs Absolute memory position immediately after the written bytes.
    function wrap(uint abs, bytes4 key, bytes memory payload) internal pure returns (uint nextAbs) {
        return wrap(abs, key, payload, payload.length);
    }

    /// @notice Wrap a validated calldata payload cursor with a new header and advance.
    /// @dev Inherits writeHeader scratch requirements and copy source/destination preconditions.
    /// @param abs Absolute memory byte position; not a packed cursor.
    /// @param key Block key.
    /// @param cur Packed source cursor containing the current position and exclusive end.
    /// @return nextAbs Absolute memory position immediately after the written bytes.
    function wrap(uint abs, bytes4 key, uint cur) internal pure returns (uint nextAbs) {
        return wrap(abs, key, uint32(cur), length(cur));
    }

    // Growable buffers: allocation, initialization, growth, reservation, finalization.

    /// @notice Allocate uninitialized capacity plus one retained scratch word and
    /// copy only the written prefix.
    /// @dev Requires written <= capacity <= uint32.max and
    /// written <= dst.length. Unwritten bytes must never be exposed or read.
    /// @param dst Destination memory buffer.
    /// @param written Number of initialized bytes to preserve.
    /// @param capacity Logical output capacity, in bytes.
    /// @return value Output buffer; retain this value because growth may relocate it.
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
    /// @param capacity Logical output capacity, in bytes.
    /// @return dst Output buffer; retain this value because growth may relocate it.
    /// @return cur Updated packed writer cursor with relative position and capacity.
    function init(uint capacity) internal pure returns (bytes memory dst, uint cur) {
        if (capacity > type(uint32).max) revert ValueOverflow();
        cur = capacity << 32;
        bytes memory empty;
        dst = grow(empty, 0, capacity);
    }

    /// @dev Cold path, reached only when size exceeds remaining capacity.
    /// @param cur Packed writer cursor containing the relative position and logical capacity.
    /// @param dst Destination memory buffer.
    /// @param size Number of output bytes to reserve.
    /// @return value Output buffer; retain this value because growth may relocate it.
    /// @return nextCur Updated packed writer cursor with relative position and capacity.
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
    /// @param cur Packed writer cursor containing the relative position and logical capacity.
    /// @param dst Destination memory buffer.
    /// @param size Number of output bytes to reserve.
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
    /// @param cur Packed writer cursor containing the relative position and logical capacity.
    /// @param dst Destination memory buffer.
    /// @return value Written output bytes with allocation padding excluded.
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
    /// @param cur Packed writer cursor containing the relative position and logical capacity.
    /// @param dst Destination memory buffer.
    /// @param account Account identifier.
    /// @return value Output buffer; retain this value because growth may relocate it.
    /// @return nextCur Updated packed writer cursor with relative position and capacity.
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
    /// @param cur Packed writer cursor containing the relative position and logical capacity.
    /// @param dst Destination memory buffer.
    /// @param asset Asset identifier.
    /// @return value Output buffer; retain this value because growth may relocate it.
    /// @return nextCur Updated packed writer cursor with relative position and capacity.
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
    /// @param cur Packed writer cursor containing the relative position and logical capacity.
    /// @param dst Destination memory buffer.
    /// @param node Node identifier.
    /// @return value Output buffer; retain this value because growth may relocate it.
    /// @return nextCur Updated packed writer cursor with relative position and capacity.
    function writeNode(uint cur, bytes memory dst, uint node) internal pure returns (bytes memory value, uint nextCur) {
        uint abs;
        (value, abs, nextCur) = reserve(cur, dst, 40);
        abs = writeHeader(abs, Keys.Node, 32);
        write32(abs, bytes32(node));
    }

    /// @notice Append ENTITY, preserving field order and full-width values.
    /// @dev Inherits reserve's initialized-writer requirements.
    /// @param cur Packed writer cursor containing the relative position and logical capacity.
    /// @param dst Destination memory buffer.
    /// @param entity Entity identifier.
    /// @return value Output buffer; retain this value because growth may relocate it.
    /// @return nextCur Updated packed writer cursor with relative position and capacity.
    function writeEntity(
        uint cur,
        bytes memory dst,
        uint entity
    ) internal pure returns (bytes memory value, uint nextCur) {
        uint abs;
        (value, abs, nextCur) = reserve(cur, dst, 40);
        abs = writeHeader(abs, Keys.Entity, 32);
        write32(abs, bytes32(entity));
    }

    /// @notice Append TRUST, preserving field order and full-width values.
    /// @dev Inherits reserve's initialized-writer requirements. Performs no registry check;
    /// only a commander that verified the ID should emit it as state.
    /// @param cur Packed writer cursor containing the relative position and logical capacity.
    /// @param dst Destination memory buffer.
    /// @param id Trusted identifier.
    /// @return value Output buffer; retain this value because growth may relocate it.
    /// @return nextCur Updated packed writer cursor with relative position and capacity.
    function writeTrust(
        uint cur,
        bytes memory dst,
        uint id
    ) internal pure returns (bytes memory value, uint nextCur) {
        uint abs;
        (value, abs, nextCur) = reserve(cur, dst, 40);
        abs = writeHeader(abs, Keys.Trust, 32);
        write32(abs, bytes32(id));
    }

    /// @notice Append STATUS, preserving field order and full-width values.
    /// @dev Inherits reserve's initialized-writer requirements.
    /// @param cur Packed writer cursor containing the relative position and logical capacity.
    /// @param dst Destination memory buffer.
    /// @param code Full-width status code.
    /// @return value Output buffer; retain this value because growth may relocate it.
    /// @return nextCur Updated packed writer cursor with relative position and capacity.
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

    /// @notice Append LIMITS, preserving field order and full-width values.
    /// @dev Inherits reserve's initialized-writer requirements.
    /// @param cur Packed writer cursor containing the relative position and logical capacity.
    /// @param dst Destination memory buffer.
    /// @param limits Packed inclusive minimum in the high 128 bits and maximum in the low 128 bits.
    /// @return value Output buffer; retain this value because growth may relocate it.
    /// @return nextCur Updated packed writer cursor with relative position and capacity.
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

    /// @notice Append a full-width scalar AMOUNT.
    /// @dev Inherits reserve's initialized-writer requirements.
    /// @param cur Packed writer cursor containing the relative position and logical capacity.
    /// @param dst Destination memory buffer.
    /// @param amount Quantity in the asset's native units.
    /// @return value Output buffer; retain this value because growth may relocate it.
    /// @return nextCur Updated packed writer cursor with relative position and capacity.
    function writeAmount(
        uint cur,
        bytes memory dst,
        uint amount
    ) internal pure returns (bytes memory value, uint nextCur) {
        uint abs;
        (value, abs, nextCur) = reserve(cur, dst, 40);
        abs = writeHeader(abs, Keys.Amount, 32);
        write32(abs, bytes32(amount));
    }

    /// @notice Append ASSET_AMOUNT, preserving field order and full-width values.
    /// @dev Inherits reserve's initialized-writer requirements.
    /// @param cur Packed writer cursor containing the relative position and logical capacity.
    /// @param dst Destination memory buffer.
    /// @param asset Asset identifier.
    /// @param amount Quantity in the asset's native units.
    /// @return value Output buffer; retain this value because growth may relocate it.
    /// @return nextCur Updated packed writer cursor with relative position and capacity.
    function writeAssetAmount(
        uint cur,
        bytes memory dst,
        bytes32 asset,
        uint amount
    ) internal pure returns (bytes memory value, uint nextCur) {
        uint abs;
        (value, abs, nextCur) = reserve(cur, dst, 72);
        abs = writeHeader(abs, Keys.AssetAmount, 64);
        abs = write32(abs, asset);
        write32(abs, bytes32(amount));
    }

    /// @notice Append PIPELINE to a growable writer, preserving full-width fields.
    /// @dev Inherits reserve's initialized-writer and lifecycle requirements.
    /// @param cur Packed writer cursor containing the relative position and logical capacity.
    /// @param dst Destination memory buffer.
    /// @param account Account identifier.
    /// @param budget Native-value budget, in wei.
    /// @return value Output buffer; retain this value because growth may relocate it.
    /// @return nextCur Updated packed writer cursor with relative position and capacity.
    function writePipeline(
        uint cur,
        bytes memory dst,
        bytes32 account,
        uint budget
    ) internal pure returns (bytes memory value, uint nextCur) {
        uint abs;
        (value, abs, nextCur) = reserve(cur, dst, 72);
        abs = writeHeader(abs, Keys.Pipeline, 64);
        abs = write32(abs, account);
        write32(abs, bytes32(budget));
    }

    /// @notice Append BALANCE to a growable writer and return its updated state.
    /// @dev Inherits reserve's writer lifecycle requirements.
    /// @param cur Packed writer cursor containing the relative position and logical capacity.
    /// @param dst Destination memory buffer.
    /// @param asset Asset identifier.
    /// @param amount Quantity in the asset's native units.
    /// @return value Output buffer; retain this value because growth may relocate it.
    /// @return nextCur Updated packed writer cursor with relative position and capacity.
    function writeBalance(
        uint cur,
        bytes memory dst,
        bytes32 asset,
        uint amount
    ) internal pure returns (bytes memory value, uint nextCur) {
        uint abs;
        (value, abs, nextCur) = reserve(cur, dst, 72);
        writeBalanceAt(abs, asset, amount);
    }

    /// @notice Write a complete BALANCE at an already reserved absolute memory position.
    /// @dev Caller owns 72 writable bytes. Does not allocate or advance a writer.
    /// @param abs Absolute memory byte position; not a packed cursor.
    /// @param asset Asset identifier.
    /// @param amount Quantity in the asset's native units.
    /// @return Absolute memory position immediately after the written bytes.
    function writeBalanceAt(uint abs, bytes32 asset, uint amount) internal pure returns (uint) {
        abs = writeHeader(abs, Keys.Balance, 64);
        abs = write32(abs, asset);
        return write32(abs, bytes32(amount));
    }

    /// @notice Write a structured BALANCE into 72 caller-owned writable bytes.
    /// @dev Does not allocate or advance a writer. Source must not overlap the destination block.
    /// @param abs Absolute memory byte position; not a packed cursor.
    /// @param value AssetAmount fields used by this operation.
    /// @return Absolute memory position immediately after the written bytes.
    function writeBalanceAt(uint abs, AssetAmount memory value) internal pure returns (uint) {
        uint payload = writeHeader(abs, Keys.Balance, 64);
        assembly ("memory-safe") {
            mcopy(payload, value, 64)
        }
        return abs + 72;
    }

    /// @notice Append ASSET_LIABILITY, preserving field order and full-width values.
    /// @dev Inherits reserve's initialized-writer requirements.
    /// @param cur Packed writer cursor containing the relative position and logical capacity.
    /// @param dst Destination memory buffer.
    /// @param asset Asset identifier.
    /// @param liability Liability asset identifier.
    /// @return value Output buffer; retain this value because growth may relocate it.
    /// @return nextCur Updated packed writer cursor with relative position and capacity.
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

    /// @notice Append ACCOUNT_ASSET, preserving field order and full-width values.
    /// @dev Inherits reserve's initialized-writer requirements.
    /// @param cur Packed writer cursor containing the relative position and logical capacity.
    /// @param dst Destination memory buffer.
    /// @param account Account identifier.
    /// @param asset Asset identifier.
    /// @return value Output buffer; retain this value because growth may relocate it.
    /// @return nextCur Updated packed writer cursor with relative position and capacity.
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

    /// @notice Append HOST_ASSET, preserving field order and full-width values.
    /// @dev Inherits reserve's initialized-writer requirements.
    /// @param cur Packed writer cursor containing the relative position and logical capacity.
    /// @param dst Destination memory buffer.
    /// @param host Host node identifier.
    /// @param asset Asset identifier.
    /// @return value Output buffer; retain this value because growth may relocate it.
    /// @return nextCur Updated packed writer cursor with relative position and capacity.
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
    /// @param cur Packed writer cursor containing the relative position and logical capacity.
    /// @param dst Destination memory buffer.
    /// @param host Host node identifier.
    /// @param asset Asset identifier.
    /// @param amount Quantity in the asset's native units.
    /// @return value Output buffer; retain this value because growth may relocate it.
    /// @return nextCur Updated packed writer cursor with relative position and capacity.
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
    /// @param cur Packed writer cursor containing the relative position and logical capacity.
    /// @param dst Destination memory buffer.
    /// @param host Host node identifier.
    /// @param asset Asset identifier.
    /// @param amount Quantity in the asset's native units.
    /// @return value Output buffer; retain this value because growth may relocate it.
    /// @return nextCur Updated packed writer cursor with relative position and capacity.
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
    /// @param cur Packed writer cursor containing the relative position and logical capacity.
    /// @param dst Destination memory buffer.
    /// @param host Host node identifier.
    /// @param asset Asset identifier.
    /// @param amount Quantity in the asset's native units.
    /// @return value Output buffer; retain this value because growth may relocate it.
    /// @return nextCur Updated packed writer cursor with relative position and capacity.
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

    /// @notice Append PAYOUT, preserving field order and full-width values.
    /// @dev Inherits reserve's initialized-writer requirements. Performs no recipient validation.
    /// @param cur Packed writer cursor containing the relative position and logical capacity.
    /// @param dst Destination memory buffer.
    /// @param recipient Account the value is paid to; zero means burn.
    /// @param asset Asset identifier.
    /// @param amount Quantity in the asset's native units.
    /// @return value Output buffer; retain this value because growth may relocate it.
    /// @return nextCur Updated packed writer cursor with relative position and capacity.
    function writePayout(
        uint cur,
        bytes memory dst,
        bytes32 recipient,
        bytes32 asset,
        uint amount
    ) internal pure returns (bytes memory value, uint nextCur) {
        uint abs;
        (value, abs, nextCur) = reserve(cur, dst, 104);
        abs = writeHeader(abs, Keys.Payout, 96);
        abs = write32(abs, recipient);
        abs = write32(abs, asset);
        write32(abs, bytes32(amount));
    }

    /// @notice Append ACCOUNT_BALANCE, preserving field order and full-width values.
    /// @dev Inherits reserve's initialized-writer requirements.
    /// @param cur Packed writer cursor containing the relative position and logical capacity.
    /// @param dst Destination memory buffer.
    /// @param account Account identifier.
    /// @param asset Asset identifier.
    /// @param amount Quantity in the asset's native units.
    /// @return value Output buffer; retain this value because growth may relocate it.
    /// @return nextCur Updated packed writer cursor with relative position and capacity.
    function writeAccountBalance(
        uint cur,
        bytes memory dst,
        bytes32 account,
        bytes32 asset,
        uint amount
    ) internal pure returns (bytes memory value, uint nextCur) {
        uint abs;
        (value, abs, nextCur) = reserve(cur, dst, 104);
        abs = writeHeader(abs, Keys.AccountBalance, 96);
        abs = write32(abs, account);
        abs = write32(abs, asset);
        write32(abs, bytes32(amount));
    }

    /// @notice Append QUOTE_REQUEST, preserving field order and full-width values.
    /// @dev Inherits reserve's initialized-writer requirements.
    /// @param cur Packed writer cursor containing the relative position and logical capacity.
    /// @param dst Destination memory buffer.
    /// @param asset Asset identifier.
    /// @param amount Quantity in the asset's native units.
    /// @param liability Liability asset identifier.
    /// @return value Output buffer; retain this value because growth may relocate it.
    /// @return nextCur Updated packed writer cursor with relative position and capacity.
    function writeQuoteRequest(
        uint cur,
        bytes memory dst,
        bytes32 asset,
        uint amount,
        bytes32 liability
    ) internal pure returns (bytes memory value, uint nextCur) {
        uint abs;
        (value, abs, nextCur) = reserve(cur, dst, 104);
        abs = writeHeader(abs, Keys.QuoteRequest, 96);
        abs = write32(abs, asset);
        abs = write32(abs, bytes32(amount));
        write32(abs, liability);
    }

    /// @notice Append ACCOUNT_AMOUNT, preserving field order and full-width values.
    /// @dev Inherits reserve's initialized-writer requirements.
    /// @param cur Packed writer cursor containing the relative position and logical capacity.
    /// @param dst Destination memory buffer.
    /// @param account Account identifier.
    /// @param asset Asset identifier.
    /// @param amount Quantity in the asset's native units.
    /// @return value Output buffer; retain this value because growth may relocate it.
    /// @return nextCur Updated packed writer cursor with relative position and capacity.
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

    /// @notice Append HOST_AMOUNT, preserving field order and full-width values.
    /// @dev Inherits reserve's initialized-writer requirements.
    /// @param cur Packed writer cursor containing the relative position and logical capacity.
    /// @param dst Destination memory buffer.
    /// @param host Host node identifier.
    /// @param asset Asset identifier.
    /// @param amount Quantity in the asset's native units.
    /// @return value Output buffer; retain this value because growth may relocate it.
    /// @return nextCur Updated packed writer cursor with relative position and capacity.
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

    /// @notice Append HOSTACCOUNT_ASSET, preserving field order and full-width values.
    /// @dev Inherits reserve's initialized-writer requirements.
    /// @param cur Packed writer cursor containing the relative position and logical capacity.
    /// @param dst Destination memory buffer.
    /// @param host Host node identifier.
    /// @param account Account identifier.
    /// @param asset Asset identifier.
    /// @return value Output buffer; retain this value because growth may relocate it.
    /// @return nextCur Updated packed writer cursor with relative position and capacity.
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
    /// @param cur Packed writer cursor containing the relative position and logical capacity.
    /// @param dst Destination memory buffer.
    /// @param asset Asset identifier.
    /// @param amount Quantity in the asset's native units.
    /// @param liability Liability asset identifier.
    /// @param debt Quantity in the liability's native units.
    /// @return value Output buffer; retain this value because growth may relocate it.
    /// @return nextCur Updated packed writer cursor with relative position and capacity.
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

    /// @notice Append HOSTACCOUNT_AMOUNT, preserving field order and full-width values.
    /// @dev Inherits reserve's initialized-writer requirements.
    /// @param cur Packed writer cursor containing the relative position and logical capacity.
    /// @param dst Destination memory buffer.
    /// @param host Host node identifier.
    /// @param account Account identifier.
    /// @param asset Asset identifier.
    /// @param amount Quantity in the asset's native units.
    /// @return value Output buffer; retain this value because growth may relocate it.
    /// @return nextCur Updated packed writer cursor with relative position and capacity.
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
    /// @param cur Packed writer cursor containing the relative position and logical capacity.
    /// @param dst Destination memory buffer.
    /// @param asset Asset identifier.
    /// @param amount Quantity in the asset's native units.
    /// @param liability Liability asset identifier.
    /// @param debt Quantity in the liability's native units.
    /// @param counterparty Settlement counterparty account, or zero for Rootzero.
    /// @return value Output buffer; retain this value because growth may relocate it.
    /// @return nextCur Updated packed writer cursor with relative position and capacity.
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
        writePositionAt(abs, asset, amount, liability, debt, counterparty);
    }

    /// @notice Write a complete POSITION at an already reserved absolute memory position.
    /// @dev Caller owns 168 writable bytes. Does not allocate or advance a writer.
    /// @param abs Absolute memory byte position; not a packed cursor.
    /// @param asset Asset identifier.
    /// @param amount Quantity in the asset's native units.
    /// @param liability Liability asset identifier.
    /// @param debt Quantity in the liability's native units.
    /// @param counterparty Settlement counterparty account, or zero for Rootzero.
    /// @return Absolute memory position immediately after the written bytes.
    function writePositionAt(
        uint abs,
        bytes32 asset,
        uint amount,
        bytes32 liability,
        uint debt,
        bytes32 counterparty
    ) internal pure returns (uint) {
        abs = writeHeader(abs, Keys.Position, 160);
        abs = write32(abs, asset);
        abs = write32(abs, bytes32(amount));
        abs = write32(abs, liability);
        abs = write32(abs, bytes32(debt));
        return write32(abs, counterparty);
    }

    /// @notice Write a structured POSITION into 168 caller-owned writable bytes.
    /// @dev Does not allocate or advance a writer. Source must not overlap the destination block.
    /// @param abs Absolute memory byte position; not a packed cursor.
    /// @param value Position fields used by this operation.
    /// @return Absolute memory position immediately after the written bytes.
    function writePositionAt(uint abs, Position memory value) internal pure returns (uint) {
        uint payload = writeHeader(abs, Keys.Position, 160);
        assembly ("memory-safe") {
            mcopy(payload, value, 160)
        }
        return abs + 168;
    }

    /// @notice Append one BOOKING from a structured value.
    /// @dev Inherits reserve's initialized-writer and lifecycle requirements.
    /// @param cur Packed writer cursor containing the relative position and logical capacity.
    /// @param dst Destination memory buffer.
    /// @param booking Exact account debit and credit legs.
    /// @return value Output buffer; retain this value because growth may relocate it.
    /// @return nextCur Updated packed writer cursor with relative position and capacity.
    function writeBooking(
        uint cur,
        bytes memory dst,
        Booking memory booking
    ) internal pure returns (bytes memory value, uint nextCur) {
        uint abs;
        (value, abs, nextCur) = reserve(cur, dst, 200);
        writeBookingAt(abs, booking);
    }

    /// @notice Write one BOOKING at an already reserved absolute memory position.
    /// @dev Caller owns 200 writable bytes. Does not allocate or advance a writer.
    /// @param abs Absolute memory byte position; not a packed cursor.
    /// @param booking Exact account debit and credit legs.
    /// @return Absolute memory position immediately after the written bytes.
    function writeBookingAt(uint abs, Booking memory booking) internal pure returns (uint) {
        uint payload = writeHeader(abs, Keys.Booking, 192);
        assembly ("memory-safe") {
            mcopy(payload, booking, 192)
        }
        return payload + 192;
    }

    // Payload blocks: generic key followed by named wrappers.

    /// @notice Append a complete validated calldata block without changing its header.
    /// @dev Source must select the complete block in calldata. Does not revalidate or advance it.
    /// @param cur Packed writer cursor containing the relative position and logical capacity.
    /// @param dst Destination memory buffer.
    /// @param dataCur Validated calldata cursor over the complete block child, including its header.
    /// @return value Output buffer; retain this value because growth may relocate it.
    /// @return nextCur Updated packed writer cursor with relative position and capacity.
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
    /// @param cur Packed writer cursor containing the relative position and logical capacity.
    /// @param dst Destination memory buffer.
    /// @param key Block key.
    /// @param data Memory payload bytes, excluding the enclosing block header.
    /// @return value Output buffer; retain this value because growth may relocate it.
    /// @return nextCur Updated packed writer cursor with relative position and capacity.
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
    /// @param cur Packed writer cursor containing the relative position and logical capacity.
    /// @param dst Destination memory buffer.
    /// @param key Block key.
    /// @param dataCur Validated calldata cursor over the block payload, excluding its header.
    /// @return value Output buffer; retain this value because growth may relocate it.
    /// @return nextCur Updated packed writer cursor with relative position and capacity.
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
    /// @param cur Packed writer cursor containing the relative position and logical capacity.
    /// @param dst Destination memory buffer.
    /// @param data Memory payload bytes, excluding the enclosing block header.
    /// @return value Output buffer; retain this value because growth may relocate it.
    /// @return nextCur Updated packed writer cursor with relative position and capacity.
    function writeList(
        uint cur,
        bytes memory dst,
        bytes memory data
    ) internal pure returns (bytes memory value, uint nextCur) {
        return writeBlock(cur, dst, Keys.List, data);
    }

    /// @notice Append LIST from a validated calldata payload cursor; empty payloads are allowed.
    /// @dev Inherits writeBlock's lifecycle and source requirements.
    /// @param cur Packed writer cursor containing the relative position and logical capacity.
    /// @param dst Destination memory buffer.
    /// @param dataCur Validated calldata cursor over the block payload, excluding its header.
    /// @return value Output buffer; retain this value because growth may relocate it.
    /// @return nextCur Updated packed writer cursor with relative position and capacity.
    function writeList(
        uint cur,
        bytes memory dst,
        uint dataCur
    ) internal pure returns (bytes memory value, uint nextCur) {
        return writeBlock(cur, dst, Keys.List, dataCur);
    }

    /// @notice Append BYTES from a memory payload; empty payloads are allowed.
    /// @dev Inherits writeBlock's lifecycle and source requirements.
    /// @param cur Packed writer cursor containing the relative position and logical capacity.
    /// @param dst Destination memory buffer.
    /// @param data Memory payload bytes, excluding the enclosing block header.
    /// @return value Output buffer; retain this value because growth may relocate it.
    /// @return nextCur Updated packed writer cursor with relative position and capacity.
    function writeBytes(
        uint cur,
        bytes memory dst,
        bytes memory data
    ) internal pure returns (bytes memory value, uint nextCur) {
        return writeBlock(cur, dst, Keys.Bytes, data);
    }

    /// @notice Append BYTES from a validated calldata payload cursor; empty payloads are allowed.
    /// @dev Inherits writeBlock's lifecycle and source requirements.
    /// @param cur Packed writer cursor containing the relative position and logical capacity.
    /// @param dst Destination memory buffer.
    /// @param dataCur Validated calldata cursor over the block payload, excluding its header.
    /// @return value Output buffer; retain this value because growth may relocate it.
    /// @return nextCur Updated packed writer cursor with relative position and capacity.
    function writeBytes(
        uint cur,
        bytes memory dst,
        uint dataCur
    ) internal pure returns (bytes memory value, uint nextCur) {
        return writeBlock(cur, dst, Keys.Bytes, dataCur);
    }

    /// @notice Append STRING from a memory payload; empty payloads are allowed.
    /// @dev Inherits writeBlock's lifecycle and source requirements.
    /// @param cur Packed writer cursor containing the relative position and logical capacity.
    /// @param dst Destination memory buffer.
    /// @param data Memory payload bytes, excluding the enclosing block header.
    /// @return value Output buffer; retain this value because growth may relocate it.
    /// @return nextCur Updated packed writer cursor with relative position and capacity.
    function writeString(
        uint cur,
        bytes memory dst,
        bytes memory data
    ) internal pure returns (bytes memory value, uint nextCur) {
        return writeBlock(cur, dst, Keys.String, data);
    }

    /// @notice Append STRING from a validated calldata payload cursor; empty payloads are allowed.
    /// @dev Inherits writeBlock's lifecycle and source requirements.
    /// @param cur Packed writer cursor containing the relative position and logical capacity.
    /// @param dst Destination memory buffer.
    /// @param dataCur Validated calldata cursor over the block payload, excluding its header.
    /// @return value Output buffer; retain this value because growth may relocate it.
    /// @return nextCur Updated packed writer cursor with relative position and capacity.
    function writeString(
        uint cur,
        bytes memory dst,
        uint dataCur
    ) internal pure returns (bytes memory value, uint nextCur) {
        return writeBlock(cur, dst, Keys.String, dataCur);
    }

    // Composites: Wrap adds child headers around payloads.

    /// @notice Append STEP by copying a complete validated calldata INPUT child.
    /// @dev Children include their headers, are not advanced, and are not revalidated.
    /// @param cur Packed writer cursor containing the relative position and logical capacity.
    /// @param dst Destination memory buffer.
    /// @param cmd Command node identifier.
    /// @param amount Native value assigned to the command, in wei.
    /// @param inputCur Validated calldata cursor over the complete INPUT child, including its header.
    /// @return value Output buffer; retain this value because growth may relocate it.
    /// @return nextCur Updated packed writer cursor with relative position and capacity.
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
    /// @param cur Packed writer cursor containing the relative position and logical capacity.
    /// @param dst Destination memory buffer.
    /// @param cmd Command node identifier.
    /// @param amount Native value assigned to the command, in wei.
    /// @param input Input block stream, excluding the enclosing container header.
    /// @return value Output buffer; retain this value because growth may relocate it.
    /// @return nextCur Updated packed writer cursor with relative position and capacity.
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
        wrap(abs, Keys.Input, input, inputSize);
    }

    /// @notice Append STEP, wrapping validated calldata payload cursors in child headers.
    /// @dev Inherits reserve and copy requirements. Sources exclude child headers,
    /// must be disjoint from writes, and are not advanced or revalidated.
    /// @param cur Packed writer cursor containing the relative position and logical capacity.
    /// @param dst Destination memory buffer.
    /// @param cmd Command node identifier.
    /// @param amount Native value assigned to the command, in wei.
    /// @param inputCur Validated calldata cursor over the INPUT payload, excluding its header.
    /// @return value Output buffer; retain this value because growth may relocate it.
    /// @return nextCur Updated packed writer cursor with relative position and capacity.
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
        wrap(abs, Keys.Input, uint32(inputCur), inputSize);
    }

    /// @notice Append SWAP by copying a complete validated LIST child, including its header.
    /// @dev Inherits reserve/copy requirements. Does not revalidate hops or route semantics.
    /// @param cur Packed writer cursor containing the relative position and logical capacity.
    /// @param dst Destination memory buffer.
    /// @param asset Asset identifier.
    /// @param amount Quantity in the asset's native units.
    /// @param hopsCur Validated calldata cursor over the complete LIST child, including its header.
    /// @return value Output buffer; retain this value because growth may relocate it.
    /// @return nextCur Updated packed writer cursor with relative position and capacity.
    function writeSwap(
        uint cur,
        bytes memory dst,
        bytes32 asset,
        uint amount,
        uint hopsCur
    ) internal pure returns (bytes memory value, uint nextCur) {
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
    /// @param cur Packed writer cursor containing the relative position and logical capacity.
    /// @param dst Destination memory buffer.
    /// @param asset Asset identifier.
    /// @param amount Quantity in the asset's native units.
    /// @param hops ASSET hop block stream, excluding the LIST child header.
    /// @return value Output buffer; retain this value because growth may relocate it.
    /// @return nextCur Updated packed writer cursor with relative position and capacity.
    function writeSwapWrap(
        uint cur,
        bytes memory dst,
        bytes32 asset,
        uint amount,
        bytes memory hops
    ) internal pure returns (bytes memory value, uint nextCur) {
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
    /// @param cur Packed writer cursor containing the relative position and logical capacity.
    /// @param dst Destination memory buffer.
    /// @param asset Asset identifier.
    /// @param amount Quantity in the asset's native units.
    /// @param hopsCur Validated calldata cursor over the LIST payload, excluding its header.
    /// @return value Output buffer; retain this value because growth may relocate it.
    /// @return nextCur Updated packed writer cursor with relative position and capacity.
    function writeSwapWrap(
        uint cur,
        bytes memory dst,
        bytes32 asset,
        uint amount,
        uint hopsCur
    ) internal pure returns (bytes memory value, uint nextCur) {
        uint hopsSize = length(hopsCur);
        uint size = 80 + hopsSize;
        uint abs;
        (value, abs, nextCur) = reserve(cur, dst, size);
        abs = writeHeader(abs, Keys.Swap, size - 8);
        abs = write32(abs, asset);
        abs = write32(abs, bytes32(amount));
        wrap(abs, Keys.List, uint32(hopsCur), hopsSize);
    }

    /// @notice Append CALL by copying a complete validated calldata BYTES child.
    /// @dev Children include their headers, are not advanced, and are not revalidated.
    /// @param cur Packed writer cursor containing the relative position and logical capacity.
    /// @param dst Destination memory buffer.
    /// @param target Target node identifier.
    /// @param value Native value assigned to the operation, in wei.
    /// @param payloadCur Validated calldata cursor over the complete BYTES child, including its header.
    /// @return output Output buffer; retain this value because growth may relocate it.
    /// @return nextCur Updated packed writer cursor with relative position and capacity.
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
    /// @param cur Packed writer cursor containing the relative position and logical capacity.
    /// @param dst Destination memory buffer.
    /// @param target Target node identifier.
    /// @param value Native value assigned to the operation, in wei.
    /// @param payload Payload bytes, excluding the BYTES child header.
    /// @return output Output buffer; retain this value because growth may relocate it.
    /// @return nextCur Updated packed writer cursor with relative position and capacity.
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
    /// @param cur Packed writer cursor containing the relative position and logical capacity.
    /// @param dst Destination memory buffer.
    /// @param target Target node identifier.
    /// @param value Native value assigned to the operation, in wei.
    /// @param payloadCur Validated calldata cursor over the BYTES payload, excluding its header.
    /// @return output Output buffer; retain this value because growth may relocate it.
    /// @return nextCur Updated packed writer cursor with relative position and capacity.
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

    /// @notice Append DISPATCH by copying a complete validated calldata BYTES child.
    /// @dev Children include their headers, are not advanced, and are not revalidated.
    /// @param cur Packed writer cursor containing the relative position and logical capacity.
    /// @param dst Destination memory buffer.
    /// @param portal Transport portal node identifier.
    /// @param resources Transport resource descriptor.
    /// @param payloadCur Validated calldata cursor over the complete BYTES child, including its header.
    /// @return value Output buffer; retain this value because growth may relocate it.
    /// @return nextCur Updated packed writer cursor with relative position and capacity.
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
    /// @param cur Packed writer cursor containing the relative position and logical capacity.
    /// @param dst Destination memory buffer.
    /// @param portal Transport portal node identifier.
    /// @param resources Transport resource descriptor.
    /// @param payload Payload bytes, excluding the BYTES child header.
    /// @return value Output buffer; retain this value because growth may relocate it.
    /// @return nextCur Updated packed writer cursor with relative position and capacity.
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
    /// @param cur Packed writer cursor containing the relative position and logical capacity.
    /// @param dst Destination memory buffer.
    /// @param portal Transport portal node identifier.
    /// @param resources Transport resource descriptor.
    /// @param payloadCur Validated calldata cursor over the BYTES payload, excluding its header.
    /// @return value Output buffer; retain this value because growth may relocate it.
    /// @return nextCur Updated packed writer cursor with relative position and capacity.
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

    /// @notice Append RELAY by copying complete validated calldata INPUT and BYTES children.
    /// @dev Children include their headers, are not advanced, and are not revalidated.
    /// @param cur Packed writer cursor containing the relative position and logical capacity.
    /// @param dst Destination memory buffer.
    /// @param inputCur Validated calldata cursor over the complete INPUT child, including its header.
    /// @param stepsCur Validated calldata cursor over the complete BYTES child, including its header.
    /// @return value Output buffer; retain this value because growth may relocate it.
    /// @return nextCur Updated packed writer cursor with relative position and capacity.
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
    /// @param cur Packed writer cursor containing the relative position and logical capacity.
    /// @param dst Destination memory buffer.
    /// @param input Input block stream, excluding the enclosing container header.
    /// @param steps Continuation STEP block stream, excluding the BYTES child header.
    /// @return value Output buffer; retain this value because growth may relocate it.
    /// @return nextCur Updated packed writer cursor with relative position and capacity.
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
        abs = wrap(abs, Keys.Input, input, inputSize);
        wrap(abs, Keys.Bytes, steps, stepsSize);
    }

    /// @notice Append RELAY, wrapping validated calldata payload cursors in child headers.
    /// @dev Inherits reserve and copy requirements. Sources exclude child headers,
    /// must be disjoint from writes, and are not advanced or revalidated.
    /// @param cur Packed writer cursor containing the relative position and logical capacity.
    /// @param dst Destination memory buffer.
    /// @param inputCur Validated calldata cursor over the INPUT payload, excluding its header.
    /// @param stepsCur Validated calldata cursor over the BYTES payload, excluding its header.
    /// @return value Output buffer; retain this value because growth may relocate it.
    /// @return nextCur Updated packed writer cursor with relative position and capacity.
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
        abs = wrap(abs, Keys.Input, uint32(inputCur), inputSize);
        wrap(abs, Keys.Bytes, uint32(stepsCur), stepsSize);
    }

    /// @notice Append RECOVER by copying a complete validated calldata BYTES child.
    /// @dev Children include their headers, are not advanced, and are not revalidated.
    /// @param cur Packed writer cursor containing the relative position and logical capacity.
    /// @param dst Destination memory buffer.
    /// @param handler Recovery handler node identifier.
    /// @param value Native value assigned to the operation, in wei.
    /// @param recoverykey Recovery lookup key.
    /// @param witnessCur Validated calldata cursor over the complete BYTES child, including its header.
    /// @return output Output buffer; retain this value because growth may relocate it.
    /// @return nextCur Updated packed writer cursor with relative position and capacity.
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
    /// @param cur Packed writer cursor containing the relative position and logical capacity.
    /// @param dst Destination memory buffer.
    /// @param handler Recovery handler node identifier.
    /// @param value Native value assigned to the operation, in wei.
    /// @param recoverykey Recovery lookup key.
    /// @param witness Recovery witness bytes, excluding the BYTES child header.
    /// @return output Output buffer; retain this value because growth may relocate it.
    /// @return nextCur Updated packed writer cursor with relative position and capacity.
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
    /// @param cur Packed writer cursor containing the relative position and logical capacity.
    /// @param dst Destination memory buffer.
    /// @param handler Recovery handler node identifier.
    /// @param value Native value assigned to the operation, in wei.
    /// @param recoverykey Recovery lookup key.
    /// @param witnessCur Validated calldata cursor over the BYTES payload, excluding its header.
    /// @return output Output buffer; retain this value because growth may relocate it.
    /// @return nextCur Updated packed writer cursor with relative position and capacity.
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

    /// @notice Append SCHEMA by copying a complete validated calldata STRING child.
    /// @dev Children include their headers, are not advanced, and are not revalidated.
    /// @param cur Packed writer cursor containing the relative position and logical capacity.
    /// @param dst Destination memory buffer.
    /// @param spec Packed block specification or named lane.
    /// @param bodyCur Validated calldata cursor over the complete STRING child, including its header.
    /// @return value Output buffer; retain this value because growth may relocate it.
    /// @return nextCur Updated packed writer cursor with relative position and capacity.
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
    /// @param cur Packed writer cursor containing the relative position and logical capacity.
    /// @param dst Destination memory buffer.
    /// @param spec Packed block specification or named lane.
    /// @param body Schema text bytes, excluding the STRING child header.
    /// @return value Output buffer; retain this value because growth may relocate it.
    /// @return nextCur Updated packed writer cursor with relative position and capacity.
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
    /// @param cur Packed writer cursor containing the relative position and logical capacity.
    /// @param dst Destination memory buffer.
    /// @param spec Packed block specification or named lane.
    /// @param bodyCur Validated calldata cursor over the STRING payload, excluding its header.
    /// @return value Output buffer; retain this value because growth may relocate it.
    /// @return nextCur Updated packed writer cursor with relative position and capacity.
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

    /// @notice Append CONTEXT by copying complete validated memory STATE and INPUT children.
    /// @dev Inherits reserve's lifecycle requirements. Children must be validated
    /// complete STATE and INPUT blocks, disjoint from destination writes.
    /// @param cur Packed writer cursor containing the relative position and logical capacity.
    /// @param dst Destination memory buffer.
    /// @param account Account identifier.
    /// @param state Complete STATE child block, including its header.
    /// @param input Complete INPUT child block, including its header.
    /// @return value Output buffer; retain this value because growth may relocate it.
    /// @return nextCur Updated packed writer cursor with relative position and capacity.
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

    /// @notice Append CONTEXT by copying complete validated calldata STATE and INPUT children.
    /// @dev Inherits reserve's lifecycle requirements. Children must be validated
    /// complete STATE and INPUT blocks, disjoint from destination writes.
    /// @param cur Packed writer cursor containing the relative position and logical capacity.
    /// @param dst Destination memory buffer.
    /// @param account Account identifier.
    /// @param stateCur Validated calldata cursor over the complete STATE child, including its header.
    /// @param inputCur Validated calldata cursor over the complete INPUT child, including its header.
    /// @return value Output buffer; retain this value because growth may relocate it.
    /// @return nextCur Updated packed writer cursor with relative position and capacity.
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

    /// @notice Append CONTEXT by wrapping memory payloads in STATE and INPUT headers.
    /// @dev Inherits reserve's lifecycle requirements. Payload ranges must be valid
    /// and disjoint from destination writes.
    /// @param cur Packed writer cursor containing the relative position and logical capacity.
    /// @param dst Destination memory buffer.
    /// @param account Account identifier.
    /// @param state State block stream, excluding the enclosing container header.
    /// @param input Input block stream, excluding the enclosing container header.
    /// @return value Output buffer; retain this value because growth may relocate it.
    /// @return nextCur Updated packed writer cursor with relative position and capacity.
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
        abs = wrap(abs, Keys.State, state, stateSize);
        wrap(abs, Keys.Input, input, inputSize);
    }

    /// @notice Append CONTEXT by wrapping validated calldata payload cursors.
    /// @dev Inherits reserve's lifecycle requirements. Payload ranges must be valid
    /// and disjoint from destination writes.
    /// @param cur Packed writer cursor containing the relative position and logical capacity.
    /// @param dst Destination memory buffer.
    /// @param account Account identifier.
    /// @param stateCur Validated calldata cursor over the STATE payload, excluding its header.
    /// @param inputCur Validated calldata cursor over the INPUT payload, excluding its header.
    /// @return value Output buffer; retain this value because growth may relocate it.
    /// @return nextCur Updated packed writer cursor with relative position and capacity.
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
        abs = wrap(abs, Keys.State, uint32(stateCur), stateSize);
        wrap(abs, Keys.Input, uint32(inputCur), inputSize);
    }

    // Creators: fixed-size blocks, payload blocks, then composites.

    /// @notice Create a complete ACCOUNT block with zero allocation padding.
    /// @dev Preserves field order and full-width values; performs no semantic validation.
    /// @param account Account identifier.
    /// @return value Complete encoded block.
    function createAccount(bytes32 account) internal pure returns (bytes memory value) {
        value = allocate(40);
        uint abs = writeHeader(pos(value, 0), Keys.Account, 32);
        write32(abs, account);
    }

    /// @notice Create a complete ASSET block with zero allocation padding.
    /// @dev Preserves field order and full-width values; performs no semantic validation.
    /// @param asset Asset identifier.
    /// @return value Complete encoded block.
    function createAsset(bytes32 asset) internal pure returns (bytes memory value) {
        value = allocate(40);
        uint abs = writeHeader(pos(value, 0), Keys.Asset, 32);
        write32(abs, asset);
    }

    /// @notice Create a complete NODE block with zero allocation padding.
    /// @dev Preserves field order and full-width values; performs no semantic validation.
    /// @param node Node identifier.
    /// @return value Complete encoded block.
    function createNode(uint node) internal pure returns (bytes memory value) {
        value = allocate(40);
        uint abs = writeHeader(pos(value, 0), Keys.Node, 32);
        write32(abs, bytes32(node));
    }

    /// @notice Create a complete ENTITY block with zero allocation padding.
    /// @dev Preserves field order and full-width values; performs no semantic validation.
    /// @param entity Entity identifier.
    /// @return value Complete encoded block.
    function createEntity(uint entity) internal pure returns (bytes memory value) {
        value = allocate(40);
        uint abs = writeHeader(pos(value, 0), Keys.Entity, 32);
        write32(abs, bytes32(entity));
    }

    /// @notice Create a complete TRUST block with zero allocation padding.
    /// @dev Preserves field order and full-width values; performs no semantic validation.
    /// @param id Trusted identifier.
    /// @return value Complete encoded block.
    function createTrust(uint id) internal pure returns (bytes memory value) {
        value = allocate(40);
        uint abs = writeHeader(pos(value, 0), Keys.Trust, 32);
        write32(abs, bytes32(id));
    }

    /// @notice Create a complete STATUS block with zero allocation padding.
    /// @dev Preserves field order and full-width values; performs no semantic validation.
    /// @param code Full-width status code.
    /// @return value Complete encoded block.
    function createStatus(uint code) internal pure returns (bytes memory value) {
        value = allocate(40);
        uint abs = writeHeader(pos(value, 0), Keys.Status, 32);
        write32(abs, bytes32(code));
    }

    /// @notice Create a complete LIMITS block with zero allocation padding.
    /// @dev Preserves field order and full-width values; performs no semantic validation.
    /// @param limits Packed inclusive minimum in the high 128 bits and maximum in the low 128 bits.
    /// @return value Complete encoded block.
    function createLimits(uint limits) internal pure returns (bytes memory value) {
        value = allocate(40);
        uint abs = writeHeader(pos(value, 0), Keys.Limits, 32);
        write32(abs, bytes32(limits));
    }

    /// @notice Create a COUNTERPARTY annotation from an account identifier.
    /// @param account Counterparty account ID, or zero for Rootzero.
    /// @return value Complete 40-byte COUNTERPARTY block with zero allocation padding.
    function createCounterparty(bytes32 account) internal pure returns (bytes memory value) {
        value = allocate(40);
        uint abs = writeHeader(pos(value, 0), Keys.Counterparty, 32);
        write32(abs, account);
    }

    /// @notice Create a complete scalar AMOUNT block with zero allocation padding.
    /// @param amount Full-width amount, encoded unchanged; the consumer defines its unit.
    /// @return value Complete 40-byte AMOUNT block.
    function createAmount(uint amount) internal pure returns (bytes memory value) {
        value = allocate(40);
        uint abs = writeHeader(pos(value, 0), Keys.Amount, 32);
        write32(abs, bytes32(amount));
    }

    /// @notice Create a complete ASSET_AMOUNT block with zero allocation padding.
    /// @dev Preserves field order and full-width values; performs no semantic validation.
    /// @param asset Asset identifier.
    /// @param amount Quantity in the asset's native units.
    /// @return value Complete encoded block.
    function createAssetAmount(bytes32 asset, uint amount) internal pure returns (bytes memory value) {
        value = allocate(72);
        uint abs = writeHeader(pos(value, 0), Keys.AssetAmount, 64);
        abs = write32(abs, asset);
        write32(abs, bytes32(amount));
    }

    /// @notice Create ENVELOPE with routing metadata, lookup key and payload digest.
    /// @dev Preserves full-width fields without hashing or validating them.
    /// @param portal Transport portal node identifier.
    /// @param resources Transport resource descriptor.
    /// @param key Forwarding or recovery lookup key.
    /// @param digest Message digest.
    /// @return value Complete encoded block.
    function createEnvelope(
        uint portal,
        uint resources,
        bytes32 key,
        bytes32 digest
    ) internal pure returns (bytes memory value) {
        value = allocate(136);
        uint abs = writeHeader(pos(value, 0), Keys.Envelope, 128);
        abs = write32(abs, bytes32(portal));
        abs = write32(abs, bytes32(resources));
        abs = write32(abs, key);
        write32(abs, digest);
    }

    /// @notice Create RESOLUTION with a recovery key and its message digest.
    /// @dev Preserves both fields without validating or changing a recovery record.
    /// @param key Forwarding or recovery lookup key.
    /// @param digest Message digest.
    /// @return value Complete encoded block.
    function createResolution(bytes32 key, bytes32 digest) internal pure returns (bytes memory value) {
        value = allocate(72);
        uint abs = writeHeader(pos(value, 0), Keys.Resolution, 64);
        abs = write32(abs, key);
        write32(abs, digest);
    }

    /// @notice Create INTRODUCTION with peer, transaction-origin account and claimed block number.
    /// @dev Preserves full-width fields without validating identity, provenance or the claim.
    /// @param peer Peer host node identifier.
    /// @param origin Transaction-origin account identifier.
    /// @param blocknum Caller-supplied block-number claim.
    /// @return value Complete encoded block.
    function createIntroduction(uint peer, bytes32 origin, uint blocknum) internal pure returns (bytes memory value) {
        value = allocate(104);
        uint abs = writeHeader(pos(value, 0), Keys.Introduction, 96);
        abs = write32(abs, bytes32(peer));
        abs = write32(abs, origin);
        write32(abs, bytes32(blocknum));
    }

    /// @notice Create a silent ENDPOINT with its ID and pure lane specs.
    /// @dev Preserves all fields without interpreting or validating them.
    /// @param id Registered endpoint node identifier.
    /// @param state State block specification or named lane.
    /// @param input Input block specification or named lane.
    /// @param output Output block specification or named lane.
    /// @return value Complete encoded block.
    function createEndpoint(uint id, uint state, uint input, uint output) internal pure returns (bytes memory value) {
        value = allocate(136);
        uint abs = writeHeader(pos(value, 0), Keys.Endpoint, 128);
        abs = write32(abs, bytes32(id));
        abs = write32(abs, bytes32(state));
        abs = write32(abs, bytes32(input));
        abs = write32(abs, bytes32(output));
    }

    /// @notice Create PIPELINE with account and initial native-value budget in that order.
    /// @dev Preserves full-width fields; does not authorize the account,
    /// transfer value, or emit an event. Payload is 64 bytes; total is 72.
    /// @param account Account identifier.
    /// @param budget Native-value budget, in wei.
    /// @return value Complete encoded block.
    function createPipeline(bytes32 account, uint budget) internal pure returns (bytes memory value) {
        value = allocate(72);
        uint abs = writeHeader(pos(value, 0), Keys.Pipeline, 64);
        abs = write32(abs, account);
        write32(abs, bytes32(budget));
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

    /// @notice Create a complete ASSET_LIABILITY block with zero allocation padding.
    /// @dev Preserves field order and full-width values; performs no semantic validation.
    /// @param asset Asset identifier.
    /// @param liability Liability asset identifier.
    /// @return value Complete encoded block.
    function createAssetLiability(bytes32 asset, bytes32 liability) internal pure returns (bytes memory value) {
        value = allocate(72);
        uint abs = writeHeader(pos(value, 0), Keys.AssetLiability, 64);
        abs = write32(abs, asset);
        write32(abs, liability);
    }

    /// @notice Create a complete ACCOUNT_ASSET block with zero allocation padding.
    /// @dev Preserves field order and full-width values; performs no semantic validation.
    /// @param account Account identifier.
    /// @param asset Asset identifier.
    /// @return value Complete encoded block.
    function createAccountAsset(bytes32 account, bytes32 asset) internal pure returns (bytes memory value) {
        value = allocate(72);
        uint abs = writeHeader(pos(value, 0), Keys.AccountAsset, 64);
        abs = write32(abs, account);
        write32(abs, asset);
    }

    /// @notice Create a complete HOST_ASSET block with zero allocation padding.
    /// @dev Preserves field order and full-width values; performs no semantic validation.
    /// @param host Host node identifier.
    /// @param asset Asset identifier.
    /// @return value Complete encoded block.
    function createHostAsset(uint host, bytes32 asset) internal pure returns (bytes memory value) {
        value = allocate(72);
        uint abs = writeHeader(pos(value, 0), Keys.HostAsset, 64);
        abs = write32(abs, bytes32(host));
        write32(abs, asset);
    }

    /// @notice Create a complete ALLOCATION block with zero allocation padding.
    /// @dev Preserves field order and full-width values; performs no semantic validation.
    /// @param host Host node identifier.
    /// @param asset Asset identifier.
    /// @param amount Quantity in the asset's native units.
    /// @return value Complete encoded block.
    function createAllocation(uint host, bytes32 asset, uint amount) internal pure returns (bytes memory value) {
        value = allocate(104);
        uint abs = writeHeader(pos(value, 0), Keys.Allocation, 96);
        abs = write32(abs, bytes32(host));
        abs = write32(abs, asset);
        write32(abs, bytes32(amount));
    }

    /// @notice Create a complete ALLOWANCE block with zero allocation padding.
    /// @dev Preserves field order and full-width values; performs no semantic validation.
    /// @param host Host node identifier.
    /// @param asset Asset identifier.
    /// @param amount Quantity in the asset's native units.
    /// @return value Complete encoded block.
    function createAllowance(uint host, bytes32 asset, uint amount) internal pure returns (bytes memory value) {
        value = allocate(104);
        uint abs = writeHeader(pos(value, 0), Keys.Allowance, 96);
        abs = write32(abs, bytes32(host));
        abs = write32(abs, asset);
        write32(abs, bytes32(amount));
    }

    /// @notice Create a complete CUSTODY block with zero allocation padding.
    /// @dev Preserves field order and full-width values; performs no semantic validation.
    /// @param host Host node identifier.
    /// @param asset Asset identifier.
    /// @param amount Quantity in the asset's native units.
    /// @return value Complete encoded block.
    function createCustody(uint host, bytes32 asset, uint amount) internal pure returns (bytes memory value) {
        value = allocate(104);
        uint abs = writeHeader(pos(value, 0), Keys.Custody, 96);
        abs = write32(abs, bytes32(host));
        abs = write32(abs, asset);
        write32(abs, bytes32(amount));
    }

    /// @notice Create a complete PAYOUT block with zero allocation padding.
    /// @dev Preserves field order and full-width values; performs no semantic validation.
    /// @param recipient Account the value is paid to; zero means burn.
    /// @param asset Asset identifier.
    /// @param amount Quantity in the asset's native units.
    /// @return value Complete encoded block.
    function createPayout(bytes32 recipient, bytes32 asset, uint amount) internal pure returns (bytes memory value) {
        value = allocate(104);
        uint abs = writeHeader(pos(value, 0), Keys.Payout, 96);
        abs = write32(abs, recipient);
        abs = write32(abs, asset);
        write32(abs, bytes32(amount));
    }

    /// @notice Create a complete ACCOUNT_BALANCE block with zero allocation padding.
    /// @dev Preserves field order and full-width values; performs no semantic validation.
    /// @param account Account identifier.
    /// @param asset Asset identifier.
    /// @param amount Quantity in the asset's native units.
    /// @return value Complete encoded block.
    function createAccountBalance(
        bytes32 account,
        bytes32 asset,
        uint amount
    ) internal pure returns (bytes memory value) {
        value = allocate(104);
        uint abs = writeHeader(pos(value, 0), Keys.AccountBalance, 96);
        abs = write32(abs, account);
        abs = write32(abs, asset);
        write32(abs, bytes32(amount));
    }

    /// @notice Create a complete QUOTE_REQUEST block with zero allocation padding.
    /// @dev Preserves field order and full-width values; performs no semantic validation.
    /// @param asset Asset identifier.
    /// @param amount Quantity in the asset's native units.
    /// @param liability Liability asset identifier.
    /// @return value Complete encoded block.
    function createQuoteRequest(
        bytes32 asset,
        uint amount,
        bytes32 liability
    ) internal pure returns (bytes memory value) {
        value = allocate(104);
        uint abs = writeHeader(pos(value, 0), Keys.QuoteRequest, 96);
        abs = write32(abs, asset);
        abs = write32(abs, bytes32(amount));
        write32(abs, liability);
    }

    /// @notice Create a complete ACCOUNT_AMOUNT block with zero allocation padding.
    /// @dev Preserves field order and full-width values; performs no semantic validation.
    /// @param account Account identifier.
    /// @param asset Asset identifier.
    /// @param amount Quantity in the asset's native units.
    /// @return value Complete encoded block.
    function createAccountAmount(
        bytes32 account,
        bytes32 asset,
        uint amount
    ) internal pure returns (bytes memory value) {
        value = allocate(104);
        uint abs = writeHeader(pos(value, 0), Keys.AccountAmount, 96);
        abs = write32(abs, account);
        abs = write32(abs, asset);
        write32(abs, bytes32(amount));
    }

    /// @notice Create a complete HOST_AMOUNT block with zero allocation padding.
    /// @dev Preserves field order and full-width values; performs no semantic validation.
    /// @param host Host node identifier.
    /// @param asset Asset identifier.
    /// @param amount Quantity in the asset's native units.
    /// @return value Complete encoded block.
    function createHostAmount(uint host, bytes32 asset, uint amount) internal pure returns (bytes memory value) {
        value = allocate(104);
        uint abs = writeHeader(pos(value, 0), Keys.HostAmount, 96);
        abs = write32(abs, bytes32(host));
        abs = write32(abs, asset);
        write32(abs, bytes32(amount));
    }

    /// @notice Create a complete HOSTACCOUNT_ASSET block with zero allocation padding.
    /// @dev Preserves field order and full-width values; performs no semantic validation.
    /// @param host Host node identifier.
    /// @param account Account identifier.
    /// @param asset Asset identifier.
    /// @return value Complete encoded block.
    function createHostAccountAsset(
        uint host,
        bytes32 account,
        bytes32 asset
    ) internal pure returns (bytes memory value) {
        value = allocate(104);
        uint abs = writeHeader(pos(value, 0), Keys.HostAccountAsset, 96);
        abs = write32(abs, bytes32(host));
        abs = write32(abs, account);
        write32(abs, asset);
    }

    /// @notice Create a complete QUOTE block with zero allocation padding.
    /// @dev Preserves field order and full-width values; performs no semantic validation.
    /// @param asset Asset identifier.
    /// @param amount Quantity in the asset's native units.
    /// @param liability Liability asset identifier.
    /// @param debt Quantity in the liability's native units.
    /// @return value Complete encoded block.
    function createQuote(
        bytes32 asset,
        uint amount,
        bytes32 liability,
        uint debt
    ) internal pure returns (bytes memory value) {
        value = allocate(136);
        uint abs = writeHeader(pos(value, 0), Keys.Quote, 128);
        abs = write32(abs, asset);
        abs = write32(abs, bytes32(amount));
        abs = write32(abs, liability);
        write32(abs, bytes32(debt));
    }

    /// @notice Create a complete HOSTACCOUNT_AMOUNT block with zero allocation padding.
    /// @dev Preserves field order and full-width values; performs no semantic validation.
    /// @param host Host node identifier.
    /// @param account Account identifier.
    /// @param asset Asset identifier.
    /// @param amount Quantity in the asset's native units.
    /// @return value Complete encoded block.
    function createHostAccountAmount(
        uint host,
        bytes32 account,
        bytes32 asset,
        uint amount
    ) internal pure returns (bytes memory value) {
        value = allocate(136);
        uint abs = writeHeader(pos(value, 0), Keys.HostAccountAmount, 128);
        abs = write32(abs, bytes32(host));
        abs = write32(abs, account);
        abs = write32(abs, asset);
        write32(abs, bytes32(amount));
    }

    /// @notice Create a complete POSITION block with zero allocation padding.
    /// @dev Preserves field order and full-width values; performs no semantic validation.
    /// @param asset Asset identifier.
    /// @param amount Quantity in the asset's native units.
    /// @param liability Liability asset identifier.
    /// @param debt Quantity in the liability's native units.
    /// @param counterparty Settlement counterparty account, or zero for Rootzero.
    /// @return value Complete encoded block.
    function createPosition(
        bytes32 asset,
        uint amount,
        bytes32 liability,
        uint debt,
        bytes32 counterparty
    ) internal pure returns (bytes memory value) {
        value = allocate(168);
        uint abs = writeHeader(pos(value, 0), Keys.Position, 160);
        abs = write32(abs, asset);
        abs = write32(abs, bytes32(amount));
        abs = write32(abs, liability);
        abs = write32(abs, bytes32(debt));
        write32(abs, counterparty);
    }

    /// @notice Create one BOOKING with full-width fields and zero allocation padding.
    /// @dev Copies the structured value; performs no semantic validation.
    /// @param booking Exact account debit and credit legs.
    /// @return value Complete encoded block.
    function createBooking(Booking memory booking) internal pure returns (bytes memory value) {
        value = allocate(200);
        writeBookingAt(pos(value, 0), booking);
    }

    // Payload creators: generic key followed by named wrappers.

    /// @notice Create a block by wrapping a memory payload in the supplied key's header.
    /// @dev Checks total size fits uint32. Does not validate schema or payload contents.
    /// @param key Block key.
    /// @param data Memory payload bytes, excluding the enclosing block header.
    /// @return value Complete encoded block.
    function createBlock(bytes4 key, bytes memory data) internal pure returns (bytes memory value) {
        uint size = data.length;
        value = allocate(8 + size);
        wrap(pos(value, 0), key, data, size);
    }

    /// @notice Create a block by wrapping a validated calldata payload cursor.
    /// @dev Requires current <= end <= calldatasize; ignores metadata and preserves
    /// the cursor. Checks total size fits uint32; does not validate payload contents.
    /// @param key Block key.
    /// @param dataCur Validated calldata cursor over the block payload, excluding its header.
    /// @return value Complete encoded block.
    function createBlock(bytes4 key, uint dataCur) internal pure returns (bytes memory value) {
        uint size = length(dataCur);
        value = allocate(8 + size);
        wrap(pos(value, 0), key, uint32(dataCur), size);
    }

    /// @notice Create LIST by wrapping a memory payload; may be empty.
    /// @dev Inherits createBlock's size and source requirements. Input excludes the header.
    /// @param data Memory payload bytes, excluding the enclosing block header.
    /// @return value Complete encoded block.
    function createList(bytes memory data) internal pure returns (bytes memory value) {
        return createBlock(Keys.List, data);
    }

    /// @notice Create LIST by wrapping a validated calldata payload cursor; may be empty.
    /// @dev Inherits createBlock's size and source requirements. Input excludes the header.
    /// @param dataCur Validated calldata cursor over the block payload, excluding its header.
    /// @return value Complete encoded block.
    function createList(uint dataCur) internal pure returns (bytes memory value) {
        return createBlock(Keys.List, dataCur);
    }

    /// @notice Create BYTES by wrapping a memory payload; may be empty.
    /// @dev Inherits createBlock's size and source requirements. Input excludes the header.
    /// @param data Memory payload bytes, excluding the enclosing block header.
    /// @return value Complete encoded block.
    function createBytes(bytes memory data) internal pure returns (bytes memory value) {
        return createBlock(Keys.Bytes, data);
    }

    /// @notice Create BYTES by wrapping a validated calldata payload cursor; may be empty.
    /// @dev Inherits createBlock's size and source requirements. Input excludes the header.
    /// @param dataCur Validated calldata cursor over the block payload, excluding its header.
    /// @return value Complete encoded block.
    function createBytes(uint dataCur) internal pure returns (bytes memory value) {
        return createBlock(Keys.Bytes, dataCur);
    }

    /// @notice Create STRING by wrapping a memory payload; may be empty.
    /// @dev Inherits createBlock's size and source requirements. Input excludes the header.
    /// @param data Memory payload bytes, excluding the enclosing block header.
    /// @return value Complete encoded block.
    function createString(bytes memory data) internal pure returns (bytes memory value) {
        return createBlock(Keys.String, data);
    }

    /// @notice Create STRING by wrapping a validated calldata payload cursor; may be empty.
    /// @dev Inherits createBlock's size and source requirements. Input excludes the header.
    /// @param dataCur Validated calldata cursor over the block payload, excluding its header.
    /// @return value Complete encoded block.
    function createString(uint dataCur) internal pure returns (bytes memory value) {
        return createBlock(Keys.String, dataCur);
    }

    // Composite creators: values and payloads, with child headers constructed here.

    /// @notice Create BOOTSTRAP with a budget and a LIST wrapping ASSET_AMOUNT bytes.
    /// @dev Copies the payload once; callers validate inner block contents.
    /// @param budget Native-value budget, in wei.
    /// @param balances ASSET_AMOUNT block stream, excluding the LIST child header.
    /// @return value Complete encoded block.
    function createBootstrap(uint budget, bytes memory balances) internal pure returns (bytes memory value) {
        uint size = 48 + balances.length;
        value = allocate(size);
        unchecked {
            uint abs = writeHeader(pos(value, 0), Keys.Bootstrap, size - 8);
            abs = write32(abs, bytes32(budget));
            wrap(abs, Keys.List, balances, balances.length);
        }
    }

    /// @notice Create VOUCH with a budget and a LIST wrapping ENTITY bytes.
    /// @dev Copies the payload once; callers validate inner block contents.
    /// @param budget Native-value budget, in wei.
    /// @param ids ENTITY block stream, excluding the LIST child header.
    /// @return value Complete encoded block.
    function createVouch(uint budget, bytes memory ids) internal pure returns (bytes memory value) {
        uint size = 48 + ids.length;
        value = allocate(size);
        unchecked {
            uint abs = writeHeader(pos(value, 0), Keys.Vouch, size - 8);
            abs = write32(abs, bytes32(budget));
            wrap(abs, Keys.List, ids, ids.length);
        }
    }

    /// @notice Encode a CONTEXT by wrapping memory-backed state and input in STATE and INPUT headers.
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
            abs = wrap(abs, Keys.State, state, stateSize);
            wrap(abs, Keys.Input, input, inputSize);
        }
    }

    /// @notice Encode a CONTEXT by wrapping calldata-backed state and input in STATE and INPUT headers.
    /// @dev Requires current <= end <= calldatasize for each cursor. Copies only
    /// their remaining ranges directly into the final output with CALLDATACOPY.
    /// No intermediate buffers, repeated bounds checks, or cursor advancement.
    /// Ignores metadata and does not skip headers or validate stream contents.
    /// The complete output size must fit uint32.
    /// @param account Account identifier to encode.
    /// @param stateCur Validated cursor over the encoded state stream.
    /// @param inputCur Validated cursor over the encoded input stream.
    /// @return value Complete encoded CONTEXT block in memory.
    function createContext(bytes32 account, uint stateCur, uint inputCur) internal pure returns (bytes memory value) {
        uint stateSize = length(stateCur);
        uint inputSize = length(inputCur);
        uint size = 56 + stateSize + inputSize;
        value = allocate(size);
        uint abs = pos(value, 0);
        unchecked {
            abs = writeHeader(abs, Keys.Context, size - 8);
            abs = write32(abs, account);
            abs = wrap(abs, Keys.State, uint32(stateCur), stateSize);
            wrap(abs, Keys.Input, uint32(inputCur), inputSize);
        }
    }

    /// @notice Create ASSET_PREIMAGE around the complete preimage bytes.
    /// @dev Preserves the asset and preimage without validating their correspondence.
    /// @param asset Asset identifier.
    /// @param preimage Complete asset identifier preimage bytes.
    /// @return value Complete encoded block.
    function createAssetPreimage(bytes32 asset, bytes memory preimage) internal pure returns (bytes memory value) {
        uint size = 48 + preimage.length;
        value = allocate(size);
        unchecked {
            uint abs = writeHeader(pos(value, 0), Keys.AssetPreimage, size - 8);
            abs = write32(abs, asset);
            wrap(abs, Keys.Bytes, preimage, preimage.length);
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

    /// @notice Create LANE metadata with its packed lane value and schema body.
    /// @param lane Packed block spec and host-local lane key, encoded unchanged.
    /// @param body Raw schema text bytes, excluding the STRING header.
    /// @return value Complete LANE block with zero allocation padding.
    function createLane(uint lane, bytes memory body) internal pure returns (bytes memory value) {
        uint size = 48 + body.length;
        value = allocate(size);
        unchecked {
            uint abs = writeHeader(pos(value, 0), Keys.Lane, size - 8);
            abs = write32(abs, bytes32(lane));
            wrap(abs, Keys.String, body, body.length);
        }
    }
}
