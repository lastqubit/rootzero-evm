// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

import {AssetAmount, AssetLiability, AccountAsset, HostAsset, AccountAmount, HostAmount, HostAccountAsset, Quote, Position, Tx} from "../core/Types.sol";
import {Blocks} from "./Blocks.sol";
import {Sizes, Specs} from "./Specs.sol";
import {Cursors, Cur} from "../utils/Cursors.sol";
import {OutOfBounds, UnconsumedData} from "../utils/Errors.sol";

using Decoders for Cur;

/// @title Decoders
/// @notice Mutable calldata block decoding through a Cur memory cursor.
library Decoders {
    using Cursors for uint;

    /// @dev Only for positions returned by block decoding from a uint32 cursor.
    /// A header plus a uint32 payload cannot move backward or overflow uint256.
    /// Keep the upper bound and all cursor metadata; general seek stays checked.
    function seekAfterBlock(uint state, uint next) private pure returns (uint) {
        if (next > uint32(state >> 32)) revert OutOfBounds();
        return (state & ~uint(type(uint32).max)) | next;
    }

    // -------------------------------------------------------------------------
    // Cur memory adapters
    // -------------------------------------------------------------------------

    /// @notice Open a calldata source without inspecting its contents.
    /// @param source Calldata region to open.
    /// @return cur Cursor spanning the complete source.
    function open(bytes calldata source) internal pure returns (Cur memory cur) {
        cur.state = Cursors.wrap(source);
    }

    /// @notice Return whether `cur` has unread bytes.
    /// @param cur Cursor to inspect.
    /// @return Whether unread bytes remain.
    function more(Cur memory cur) internal pure returns (bool) {
        return cur.state.more();
    }

    /// @notice Require the complete decoder source to have been consumed.
    /// @param cur Decoder cursor to close.
    function close(Cur memory cur) internal pure {
        if (cur.state.more()) revert UnconsumedData();
    }

    /// @notice Return the cursor's current absolute calldata position.
    /// @param cur Cursor to inspect.
    /// @return Current absolute calldata position.
    function absolute(Cur memory cur) internal pure returns (uint) {
        return cur.state.position();
    }

    /// @notice Validate and consume the next block from a cursor.
    /// @param cur Cursor advanced over the complete block.
    /// @param spec Expected block specification.
    /// @return body Absolute position of the first payload byte.
    /// @return end Absolute position immediately after the payload.
    function consume(Cur memory cur, uint spec) internal pure returns (uint body, uint end) {
        (body, end) = Blocks.enter(cur.state.position(), spec);
        cur.state = seekAfterBlock(cur.state, end);
    }

    /// @notice Validate a known key and consume the next block from a cursor.
    /// @dev Validates no payload-size constraint beyond proving the complete block
    /// lies within the cursor's logical region.
    /// @param cur Cursor advanced over the complete block.
    /// @param key Expected block key.
    /// @return body Absolute position of the first payload byte.
    /// @return end Absolute position immediately after the payload.
    function consume(Cur memory cur, bytes4 key) internal pure returns (uint body, uint end) {
        (body, end) = Blocks.enter(cur.state.position(), key);
        cur.state = seekAfterBlock(cur.state, end);
    }

    /// @notice Consume a matching empty block from a cursor when present.
    /// @param cur Cursor advanced only when the matching block is empty.
    /// @param key Expected block key.
    /// @return Whether an empty block was consumed.
    function tryConsumeEmpty(Cur memory cur, bytes4 key) internal pure returns (bool) {
        (uint position, uint end) = cur.state.bounds();
        (bytes4 current, uint len) = Blocks.peek(position, end);
        if (current != key || len != 0) return false;
        cur.state = seekAfterBlock(cur.state, position + Sizes.Header);
        return true;
    }

    /// @notice Validate and enter the payload of the next block in a cursor.
    /// @dev The cursor remains in its existing frame so callers can decode child
    /// blocks in place. Callers should prove complete payload consumption with
    /// `cur.state.expect(end)` after decoding the children.
    /// @param cur Cursor advanced over the block header to its payload.
    /// @param spec Expected parent block specification.
    /// @return body Absolute position of the first payload byte.
    /// @return end Absolute position immediately after the payload.
    function enter(Cur memory cur, uint spec) internal pure returns (uint body, uint end) {
        uint state = cur.state;
        (body, end) = Blocks.enter(uint32(state), spec);
        if (body > uint32(state >> 32)) revert OutOfBounds();
        cur.state = (state & ~uint(type(uint32).max)) | body;
    }

    /// @notice Validate and enter the payload of the next keyed block in a cursor.
    /// @dev Validates no payload-size constraint. Callers should prove complete
    /// payload consumption with `cur.state.expect(end)` after decoding.
    /// @param cur Cursor advanced over the block header to its payload.
    /// @param key Expected parent block key.
    /// @return body Absolute position of the first payload byte.
    /// @return end Absolute position immediately after the payload.
    function enter(Cur memory cur, bytes4 key) internal pure returns (uint body, uint end) {
        uint state = cur.state;
        (body, end) = Blocks.enter(uint32(state), key);
        if (body > uint32(state >> 32)) revert OutOfBounds();
        cur.state = (state & ~uint(type(uint32).max)) | body;
    }

    /// @notice Validate a parent block and advance over a fixed payload prefix.
    /// @dev `amount` is relative to the payload start and cannot exceed the
    /// current parent payload. The returned `abs` remains the payload start.
    /// @param cur Cursor advanced over the block header and fixed prefix.
    /// @param spec Expected parent block specification.
    /// @param amount Number of initial payload bytes to advance over.
    /// @return body Absolute position of the first payload byte.
    /// @return end Absolute position immediately after the payload.
    function enter(Cur memory cur, uint spec, uint amount) internal pure returns (uint body, uint end) {
        uint state = cur.state;
        uint next;
        (body, next, end) = Blocks.enter(uint32(state), spec, amount);
        if (next > uint32(state >> 32)) revert OutOfBounds();
        cur.state = (state & ~uint(type(uint32).max)) | next;
    }

    /// @notice Validate a keyed parent block and advance over a fixed payload prefix.
    /// @dev Validates no payload-size constraint beyond the requested prefix.
    /// The returned `body` remains the payload start.
    /// @param cur Cursor advanced over the block header and fixed prefix.
    /// @param key Expected parent block key.
    /// @param amount Number of initial payload bytes to advance over.
    /// @return body Absolute position of the first payload byte.
    /// @return end Absolute position immediately after the payload.
    function enter(Cur memory cur, bytes4 key, uint amount) internal pure returns (uint body, uint end) {
        uint state = cur.state;
        uint next;
        (body, next, end) = Blocks.enter(uint32(state), key, amount);
        if (next > uint32(state >> 32)) revert OutOfBounds();
        cur.state = (state & ~uint(type(uint32).max)) | next;
    }

    /// @notice Advance a cursor by a raw byte count.
    /// @dev No block header or schema is validated.
    /// @param cur Cursor advanced by `amount` bytes.
    /// @param amount Number of bytes to advance.
    function advance(Cur memory cur, uint amount) internal pure {
        cur.state = cur.state.advance(amount);
    }

    /// @notice Take a raw byte range from the cursor.
    /// @dev No block header or schema is validated.
    /// @param cur Cursor advanced by `amount` bytes.
    /// @param amount Number of bytes to take.
    /// @return abs Absolute position of the first taken byte.
    function take(Cur memory cur, uint amount) internal pure returns (uint abs) {
        (cur.state, abs) = cur.state.consume(amount);
    }

    /// @notice Require a decoder cursor to be at absolute position `abs`.
    /// @param cur Cursor whose position is validated.
    /// @param abs Expected absolute position.
    function expect(Cur memory cur, uint abs) internal pure {
        cur.state.expect(abs);
    }

    /// @notice Create a child cursor over unread absolute range `[from, to)`.
    /// @param cur Parent cursor.
    /// @param from Inclusive absolute start.
    /// @param to Exclusive absolute end.
    /// @return out Child cursor spanning the selected range.
    function slice(Cur memory cur, uint from, uint to) internal pure returns (Cur memory out) {
        out.state = cur.state.slice(from, to);
    }

    /// @notice Return the unread calldata region represented by `cur`.
    /// @param cur Cursor whose calldata is returned.
    /// @return data Unread cursor region from its current position.
    function raw(Cur memory cur) internal pure returns (bytes calldata data) {
        (uint position, uint end) = cur.state.bounds();
        if (end > msg.data.length) {
            revert Blocks.MalformedBlocks();
        }
        data = msg.data[position:end];
    }

    /// @notice Return absolute calldata range `[from, to)` from `cur`.
    /// @param cur Cursor containing the range.
    /// @param from Inclusive absolute start.
    /// @param to Exclusive absolute end.
    /// @return data Selected calldata range.
    function raw(Cur memory cur, uint from, uint to) internal pure returns (bytes calldata data) {
        (uint position, uint end) = cur.state.bounds();
        if (from < position || from > to || to > end || end > msg.data.length) revert Blocks.MalformedBlocks();
        data = msg.data[from:to];
    }

    /// @notice Hash absolute calldata range `[from, to)` from `cur`.
    /// @param cur Cursor containing the range.
    /// @param from Inclusive absolute start.
    /// @param to Exclusive absolute end.
    /// @return Hash of the selected calldata.
    function hash(Cur memory cur, uint from, uint to) internal pure returns (bytes32) {
        return keccak256(raw(cur, from, to));
    }

    /// @notice Read the block header at absolute `position` without advancing.
    /// @param cur Cursor containing the block.
    /// @param position Absolute block position.
    /// @return key Block key.
    /// @return len Payload length.
    function peek(Cur memory cur, uint position) internal pure returns (bytes4 key, uint len) {
        if (position < cur.state.position()) revert Blocks.MalformedBlocks();
        return Blocks.peek(position, cur.state.limit());
    }

    /// @notice Return the absolute position immediately after the current block.
    /// @param cur Cursor positioned at a block.
    /// @return Absolute position after the block.
    function past(Cur memory cur) internal pure returns (uint) {
        uint position = cur.state.position();
        (, uint len) = peek(cur, position);
        return position + Sizes.Header + len;
    }

    /// @notice Return whether `key` occurs at absolute `position`.
    /// @param cur Cursor containing the position.
    /// @param position Absolute block position.
    /// @param key Expected block key.
    /// @return Whether the key occurs at the position.
    function hasAt(Cur memory cur, uint position, bytes4 key) internal pure returns (bool) {
        if (position < cur.state.position()) return false;
        return Blocks.hasAt(position, cur.state.limit(), key);
    }

    /// @notice Return whether the current block has `key`.
    /// @param cur Cursor positioned at a block.
    /// @param key Expected block key.
    /// @return Whether the current block has the key.
    function isAt(Cur memory cur, bytes4 key) internal pure returns (bool) {
        return Blocks.hasAt(cur.state.position(), cur.state.limit(), key);
    }

    /// @notice Return whether the current block has `key` and an empty payload.
    /// @param cur Cursor positioned at a block.
    /// @param key Expected block key.
    /// @return Whether a complete matching empty block header occurs at the current position.
    function isEmpty(Cur memory cur, bytes4 key) internal pure returns (bool) {
        return Blocks.isEmpty(cur.state.position(), cur.state.limit(), key);
    }

    /// @notice Find `key` at or after absolute `position`.
    /// @param cur Cursor to search.
    /// @param position Absolute search position.
    /// @param key Block key to find.
    /// @return Absolute position of the matching block.
    function find(Cur memory cur, uint position, bytes4 key) internal pure returns (uint) {
        if (position < cur.state.position()) revert Blocks.MalformedBlocks();
        return Blocks.find(position, cur.state.limit(), key);
    }

    /// @notice Find `key` at or after the current cursor position.
    /// @param cur Cursor to search from its current position.
    /// @param key Block key to find.
    /// @return Absolute position of the matching block.
    function find(Cur memory cur, bytes4 key) internal pure returns (uint) {
        return Blocks.find(cur.state.position(), cur.state.limit(), key);
    }

    /// @notice Count consecutive blocks with `key` from the current cursor position.
    /// @dev Does not advance the cursor.
    /// @param cur Cursor to inspect.
    /// @param key Block key forming the run.
    /// @return count Number of consecutive matching blocks.
    function run(Cur memory cur, bytes4 key) internal pure returns (uint count) {
        (count, ) = Blocks.run(cur.state.position(), cur.state.limit(), key);
    }

    /// @notice Consume one LIST block and return a cursor over its items.
    /// @param cur Cursor advanced past the list.
    /// @return items Cursor spanning the list payload.
    function list(Cur memory cur) internal pure returns (Cur memory items) {
        return list(cur, Specs.List);
    }

    /// @notice Consume a list block described by `spec` and return a cursor over its items.
    /// @param cur Cursor advanced past the list.
    /// @param spec Custom list block specification.
    /// @return items Cursor spanning the list payload.
    function list(Cur memory cur, uint spec) internal pure returns (Cur memory items) {
        (uint abs, uint end) = consume(cur, spec);
        items.state = Cursors.create(abs, end, 0);
    }

    /// @notice Consume one block with `key` and return its complete encoded region.
    /// @param cur Cursor advanced past the block.
    /// @param key Expected block key.
    /// @return out Cursor spanning the complete encoded block.
    function takeBlock(Cur memory cur, bytes4 key) internal pure returns (Cur memory out) {
        uint abs = cur.state.position();
        (, uint end) = consume(cur, key);
        out.state = Cursors.create(abs, end, 0);
    }

    // -------------------------------------------------------------------------
    // Generic block decoding
    // -------------------------------------------------------------------------

    /// @notice Decode and consume a block described by `spec`.
    /// @param cur Cursor advanced past the block.
    /// @param spec Expected block specification.
    /// @return data Decoded payload.
    function unpackRaw(Cur memory cur, uint spec) internal pure returns (bytes calldata data) {
        uint end;
        (data, end) = Blocks.unpackRaw(cur.state.position(), spec);
        cur.state = seekAfterBlock(cur.state, end);
    }

    /// @notice Decode and consume one BYTES block.
    /// @param cur Cursor advanced past the block.
    /// @return data Decoded byte payload.
    function unpackBytes(Cur memory cur) internal pure returns (bytes calldata data) {
        uint end;
        (data, end) = Blocks.unpackBytes(cur.state.position());
        cur.state = seekAfterBlock(cur.state, end);
    }

    /// @notice Decode and consume one STRING block.
    /// @param cur Cursor advanced past the block.
    /// @return data Decoded string payload.
    function unpackString(Cur memory cur) internal pure returns (string memory data) {
        bytes calldata value;
        uint end;
        (value, end) = Blocks.unpackString(cur.state.position());
        data = string(value);
        cur.state = seekAfterBlock(cur.state, end);
    }

    // -------------------------------------------------------------------------
    // Execution-compatible fixed-width block decoding
    // -------------------------------------------------------------------------

    /// @dev Return the next raw calldata word and advance by `size` bytes.
    function nextN(Cur memory cur, uint size) private pure returns (bytes32 value) {
        value = Blocks.read32(take(cur, size));
    }

    /// @notice Return the next raw byte and advance the cursor by one byte.
    function next1(Cur memory cur) internal pure returns (bytes1 value) {
        value = bytes1(nextN(cur, 1));
    }

    /// @notice Return the next two raw bytes and advance the cursor by two bytes.
    function next2(Cur memory cur) internal pure returns (bytes2 value) {
        value = bytes2(nextN(cur, 2));
    }

    /// @notice Return the next four raw bytes and advance the cursor by four bytes.
    function next4(Cur memory cur) internal pure returns (bytes4 value) {
        value = bytes4(nextN(cur, 4));
    }

    /// @notice Return the next eight raw bytes and advance the cursor by eight bytes.
    function next8(Cur memory cur) internal pure returns (bytes8 value) {
        value = bytes8(nextN(cur, 8));
    }

    /// @notice Return the next sixteen raw bytes and advance the cursor by sixteen bytes.
    function next16(Cur memory cur) internal pure returns (bytes16 value) {
        value = bytes16(nextN(cur, 16));
    }

    /// @notice Return the next raw calldata word and advance the cursor.
    /// @param cur Cursor advanced by one word.
    /// @return value Raw word at the cursor's previous position.
    function next32(Cur memory cur) internal pure returns (bytes32 value) {
        value = nextN(cur, Sizes.Word);
    }

    /// @notice Decode one fixed 32-byte payload described by `spec`.
    /// @param cur Cursor advanced past the block.
    /// @param spec Expected block specification.
    /// @return value Decoded payload word.
    function unpack32(Cur memory cur, uint spec) internal pure returns (bytes32 value) {
        uint abs;
        (cur.state, abs) = cur.state.consume(Sizes.B32);
        uint64 head;
        assembly ("memory-safe") { head := shr(192, calldataload(abs)) }
        if (head != ((uint64(uint32(Specs.key(spec))) << 32) | 32)) revert Blocks.InvalidBlock();
        assembly ("memory-safe") {
            value := calldataload(add(abs, 0x08))
        }
    }

    /// @notice Decode and consume one ACCOUNT block.
    /// @param cur Cursor advanced past the block.
    /// @return account Decoded account identifier.
    function unpackAccount(Cur memory cur) internal pure returns (bytes32 account) {
        uint abs;
        (cur.state, abs) = cur.state.consume(Sizes.B32);
        account = Blocks.unpackAccount(abs);
    }

    /// @notice Decode and consume one NODE block.
    /// @param cur Cursor advanced past the block.
    /// @return node Decoded node identifier.
    function unpackNode(Cur memory cur) internal pure returns (uint node) {
        uint abs;
        (cur.state, abs) = cur.state.consume(Sizes.B32);
        node = Blocks.unpackNode(abs);
    }

    /// @notice Decode and consume one BOOTSTRAP block.
    /// @param cur Cursor advanced past the block.
    /// @return asset Decoded asset identifier.
    /// @return amount Decoded balance amount.
    /// @return budget Decoded native-value budget contribution.
    function unpackBootstrap(Cur memory cur) internal pure returns (bytes32 asset, uint amount, uint budget) {
        uint abs;
        (cur.state, abs) = cur.state.consume(Sizes.Bootstrap);
        return Blocks.unpackBootstrap(abs);
    }

    /// @notice Decode and consume one ASSET block.
    /// @param cur Cursor advanced past the block.
    /// @return asset Decoded asset identifier.
    function unpackAsset(Cur memory cur) internal pure returns (bytes32 asset) {
        uint abs;
        (cur.state, abs) = cur.state.consume(Sizes.B32);
        asset = Blocks.unpackAsset(abs);
    }

    /// @notice Decode and consume one ASSET_LIABILITY block.
    /// @param cur Cursor advanced past the block.
    /// @return asset Decoded asset identifier.
    /// @return liability Decoded liability identifier.
    function unpackAssetLiability(Cur memory cur) internal pure returns (bytes32 asset, bytes32 liability) {
        uint abs;
        (cur.state, abs) = cur.state.consume(Sizes.B64);
        (asset, liability) = Blocks.unpackAssetLiability(abs);
    }

    /// @notice Decode and consume one ACCOUNT_ASSET block.
    /// @param cur Cursor advanced past the block.
    /// @return account Decoded account identifier.
    /// @return asset Decoded asset identifier.
    function unpackAccountAsset(Cur memory cur) internal pure returns (bytes32 account, bytes32 asset) {
        uint abs;
        (cur.state, abs) = cur.state.consume(Sizes.B64);
        (account, asset) = Blocks.unpackAccountAsset(abs);
    }

    /// @notice Decode and consume one HOST_ASSET block.
    /// @param cur Cursor advanced past the block.
    /// @return host Decoded host identifier.
    /// @return asset Decoded asset identifier.
    function unpackHostAsset(Cur memory cur) internal pure returns (uint host, bytes32 asset) {
        uint abs;
        (cur.state, abs) = cur.state.consume(Sizes.HostAsset);
        (host, asset) = Blocks.unpackHostAsset(abs);
    }

    /// @notice Decode and consume one AMOUNT block.
    /// @param cur Cursor advanced past the block.
    /// @return asset Decoded asset identifier.
    /// @return amount Decoded amount.
    function unpackAmount(Cur memory cur) internal pure returns (bytes32 asset, uint amount) {
        uint abs;
        (cur.state, abs) = cur.state.consume(Sizes.Amount);
        (asset, amount) = Blocks.unpackAmount(abs);
    }

    /// @notice Decode and consume one BALANCE block.
    /// @param cur Cursor advanced past the block.
    /// @return asset Decoded asset identifier.
    /// @return amount Decoded balance.
    function unpackBalance(Cur memory cur) internal pure returns (bytes32 asset, uint amount) {
        uint abs;
        (cur.state, abs) = cur.state.consume(Sizes.Balance);
        (asset, amount) = Blocks.unpackBalance(abs);
    }

    /// @notice Decode and consume one ACCOUNT_AMOUNT block.
    /// @param cur Cursor advanced past the block.
    /// @return account Decoded account identifier.
    /// @return asset Decoded asset identifier.
    /// @return amount Decoded amount.
    function unpackAccountAmount(
        Cur memory cur
    ) internal pure returns (bytes32 account, bytes32 asset, uint amount) {
        uint abs;
        (cur.state, abs) = cur.state.consume(Sizes.B96);
        (account, asset, amount) = Blocks.unpackAccountAmount(abs);
    }

    /// @notice Decode one ALLOCATION block into its structured value.
    /// @param cur Cursor advanced past the block.
    /// @return value Structured allocation.
    function unpackAllocationValue(Cur memory cur) internal pure returns (HostAmount memory value) {
        uint abs;
        (cur.state, abs) = cur.state.consume(Sizes.B96);
        (value.host, value.asset, value.amount) = Blocks.unpackAllocation(abs);
    }

    /// @notice Decode and consume one ALLOWANCE block.
    /// @param cur Cursor advanced past the block.
    /// @return host Decoded host identifier.
    /// @return asset Decoded asset identifier.
    /// @return amount Decoded allowance.
    function unpackAllowance(Cur memory cur) internal pure returns (uint host, bytes32 asset, uint amount) {
        uint abs;
        (cur.state, abs) = cur.state.consume(Sizes.B96);
        (host, asset, amount) = Blocks.unpackAllowance(abs);
    }

    /// @notice Decode and consume one TRANSACTION block.
    /// @param cur Cursor advanced past the block.
    /// @return from Decoded debit account.
    /// @return to Decoded credit account.
    /// @return asset Decoded asset identifier.
    /// @return amount Decoded transaction amount.
    function unpackTransaction(
        Cur memory cur
    ) internal pure returns (bytes32 from, bytes32 to, bytes32 asset, uint amount) {
        uint abs;
        (cur.state, abs) = cur.state.consume(Sizes.Transaction);
        (from, to, asset, amount) = Blocks.unpackTransaction(abs);
    }

    // -------------------------------------------------------------------------
    // Execution-compatible dynamic block decoding
    // -------------------------------------------------------------------------

    /// @notice Decode and consume one CALL block.
    /// @param cur Cursor advanced past the block.
    /// @return target Decoded call target.
    /// @return resources Decoded packed resources.
    /// @return data Decoded call payload.
    function unpackCall(
        Cur memory cur
    ) internal pure returns (uint target, uint resources, bytes calldata data) {
        uint abs = cur.state.position();
        uint end;
        (target, resources, data, end) = Blocks.unpackCall(abs);
        cur.state = seekAfterBlock(cur.state, end);
    }

    /// @notice Decode and consume one ANNOTATION block.
    /// @param cur Cursor advanced past the block.
    /// @return entity Decoded entity identifier.
    /// @return data Decoded annotation block stream.
    function unpackAnnotation(
        Cur memory cur
    ) internal pure returns (uint entity, bytes calldata data) {
        uint abs = cur.state.position();
        uint end;
        (entity, data, end) = Blocks.unpackAnnotation(abs);
        cur.state = seekAfterBlock(cur.state, end);
    }

    /// @notice Decode and consume one CONTEXT block.
    /// @param cur Cursor advanced past the block.
    /// @return account Decoded account identifier.
    /// @return state Decoded state payload.
    /// @return input Decoded input payload.
    function unpackContext(
        Cur memory cur
    ) internal pure returns (bytes32 account, bytes calldata state, bytes calldata input) {
        uint abs = cur.state.position();
        uint end;
        (account, state, input, end) = Blocks.unpackContext(abs);
        cur.state = seekAfterBlock(cur.state, end);
    }

    /// @notice Decode and consume one DISPATCH block.
    /// @param cur Cursor advanced past the block.
    /// @return portal Decoded destination portal.
    /// @return resources Decoded packed resources.
    /// @return payload Decoded dispatch payload.
    function unpackDispatch(
        Cur memory cur
    ) internal pure returns (uint portal, uint resources, bytes calldata payload) {
        uint abs = cur.state.position();
        uint end;
        (portal, resources, payload, end) = Blocks.unpackDispatch(abs);
        cur.state = seekAfterBlock(cur.state, end);
    }

    /// @notice Decode and consume one LABEL block.
    /// @param cur Cursor advanced past the block.
    /// @return namespace Decoded label namespace.
    /// @return name Decoded label text.
    function unpackLabel(Cur memory cur) internal pure returns (bytes32 namespace, string memory name) {
        uint abs = cur.state.position();
        uint end;
        (namespace, name, end) = Blocks.unpackLabel(abs);
        cur.state = seekAfterBlock(cur.state, end);
    }

    /// @notice Decode and consume one SCHEMA block.
    /// @param cur Cursor advanced past the block.
    /// @return spec Decoded block specification.
    /// @return body Decoded schema DSL string, including any `name:` prefix.
    function unpackSchema(Cur memory cur) internal pure returns (uint spec, string memory body) {
        uint abs = cur.state.position();
        uint end;
        (spec, body, end) = Blocks.unpackSchema(abs);
        cur.state = seekAfterBlock(cur.state, end);
    }

    /// @notice Decode and consume one RECOVER block.
    /// @param cur Cursor advanced past the block.
    /// @return handler Decoded recovery handler.
    /// @return resources Decoded packed resources.
    /// @return key Decoded recovery key.
    /// @return witness Decoded recovery witness.
    function unpackRecover(
        Cur memory cur
    ) internal pure returns (uint handler, uint resources, bytes32 key, bytes calldata witness) {
        uint abs = cur.state.position();
        uint end;
        (handler, resources, key, witness, end) = Blocks.unpackRecover(abs);
        cur.state = seekAfterBlock(cur.state, end);
    }

    // -------------------------------------------------------------------------
    // Additional semantic block decoding
    // -------------------------------------------------------------------------

    /// @notice Decode one ACCOUNT_ASSET block into its structured value.
    /// @param cur Cursor advanced past the block.
    /// @return value Structured account and asset.
    function unpackAccountAssetValue(Cur memory cur) internal pure returns (AccountAsset memory value) {
        (value.account, value.asset) = unpackAccountAsset(cur);
    }

    /// @notice Decode one ASSET_LIABILITY block into its structured value.
    /// @param cur Cursor advanced past the block.
    /// @return value Structured asset and liability pair.
    function unpackAssetLiabilityValue(Cur memory cur) internal pure returns (AssetLiability memory value) {
        (value.asset, value.liability) = unpackAssetLiability(cur);
    }

    /// @notice Decode one HOST_ASSET block into its structured value.
    /// @param cur Cursor advanced past the block.
    /// @return value Structured host and asset.
    function unpackHostAssetValue(Cur memory cur) internal pure returns (HostAsset memory value) {
        (value.host, value.asset) = unpackHostAsset(cur);
    }

    /// @notice Decode one AMOUNT block into its structured value.
    /// @param cur Cursor advanced past the block.
    /// @return value Structured asset amount.
    function unpackAmountValue(Cur memory cur) internal pure returns (AssetAmount memory value) {
        (value.asset, value.amount) = unpackAmount(cur);
    }

    /// @notice Decode one BALANCE block into its structured value.
    /// @param cur Cursor advanced past the block.
    /// @return value Structured asset balance.
    function unpackBalanceValue(Cur memory cur) internal pure returns (AssetAmount memory value) {
        (value.asset, value.amount) = unpackBalance(cur);
    }

    /// @notice Decode and consume one HOST_ACCOUNT_ASSET block.
    /// @param cur Cursor advanced past the block.
    /// @return host Decoded host identifier.
    /// @return account Decoded account identifier.
    /// @return asset Decoded asset identifier.
    function unpackHostAccountAsset(
        Cur memory cur
    ) internal pure returns (uint host, bytes32 account, bytes32 asset) {
        uint abs;
        (cur.state, abs) = cur.state.consume(Sizes.B96);
        (host, account, asset) = Blocks.unpackHostAccountAsset(abs);
    }

    /// @notice Decode one HOST_ACCOUNT_ASSET block into its structured value.
    /// @param cur Cursor advanced past the block.
    /// @return value Structured host, account, and asset.
    function unpackHostAccountAssetValue(Cur memory cur) internal pure returns (HostAccountAsset memory value) {
        (value.host, value.account, value.asset) = unpackHostAccountAsset(cur);
    }

    /// @notice Decode one ACCOUNT_AMOUNT block into its structured value.
    /// @param cur Cursor advanced past the block.
    /// @return value Structured account amount.
    function unpackAccountAmountValue(Cur memory cur) internal pure returns (AccountAmount memory value) {
        (value.account, value.asset, value.amount) = unpackAccountAmount(cur);
    }

    /// @notice Decode and consume one ALLOCATION block.
    /// @param cur Cursor advanced past the block.
    /// @return host Decoded host identifier.
    /// @return asset Decoded asset identifier.
    /// @return amount Decoded allocation.
    function unpackAllocation(Cur memory cur) internal pure returns (uint host, bytes32 asset, uint amount) {
        uint abs;
        (cur.state, abs) = cur.state.consume(Sizes.B96);
        (host, asset, amount) = Blocks.unpackAllocation(abs);
    }

    /// @notice Decode one ALLOWANCE block into its structured value.
    /// @param cur Cursor advanced past the block.
    /// @return value Structured allowance.
    function unpackAllowanceValue(Cur memory cur) internal pure returns (HostAmount memory value) {
        (value.host, value.asset, value.amount) = unpackAllowance(cur);
    }

    /// @notice Decode and consume one CUSTODY block.
    /// @param cur Cursor advanced past the block.
    /// @return host Decoded host identifier.
    /// @return asset Decoded asset identifier.
    /// @return amount Decoded custody amount.
    function unpackCustody(Cur memory cur) internal pure returns (uint host, bytes32 asset, uint amount) {
        uint abs;
        (cur.state, abs) = cur.state.consume(Sizes.Custody);
        (host, asset, amount) = Blocks.unpackCustody(abs);
    }

    /// @notice Decode one CUSTODY block into its structured value.
    /// @param cur Cursor advanced past the block.
    /// @return value Structured custody amount.
    function unpackCustodyValue(Cur memory cur) internal pure returns (HostAmount memory value) {
        (value.host, value.asset, value.amount) = unpackCustody(cur);
    }

    /// @notice Decode and consume one LIMITS block.
    /// @return limits Packed minimum asset amount (high 128 bits) and maximum debt (low 128 bits).
    function unpackLimits(Cur memory cur) internal pure returns (uint limits) {
        uint abs;
        (cur.state, abs) = cur.state.consume(Sizes.Limits);
        limits = Blocks.unpackLimits(abs);
    }

    /// @notice Decode and consume one QUOTE input with minimum amount and maximum debt.
    function unpackQuote(Cur memory cur) internal pure returns (bytes32 asset, bytes32 liability, uint limits) {
        uint abs;
        (cur.state, abs) = cur.state.consume(Sizes.Quote);
        (asset, liability, limits) = Blocks.unpackQuote(abs);
    }

    /// @notice Decode one QUOTE into its structured value.
    function unpackQuoteValue(Cur memory cur) internal pure returns (Quote memory quote) {
        (quote.asset, quote.liability, quote.limits) = unpackQuote(cur);
    }

    /// @notice Decode and consume one POSITION block.
    function unpackPosition(
        Cur memory cur
    ) internal pure returns (bytes32 asset, uint amount, bytes32 liability, uint debt, bytes32 counterparty) {
        uint abs;
        (cur.state, abs) = cur.state.consume(Sizes.Position);
        (asset, amount, liability, debt, counterparty) = Blocks.unpackPosition(abs);
    }

    /// @notice Decode one POSITION block into its structured value.
    function unpackPositionValue(Cur memory cur) internal pure returns (Position memory value) {
        (value.asset, value.amount, value.liability, value.debt, value.counterparty) = unpackPosition(cur);
    }

    /// @notice Decode one TRANSACTION block into its structured value.
    /// @param cur Cursor advanced past the block.
    /// @return value Structured transaction.
    function unpackTransactionValue(Cur memory cur) internal pure returns (Tx memory value) {
        (value.from, value.to, value.asset, value.amount) = unpackTransaction(cur);
    }

    /// @notice Decode and consume one STEP block.
    /// @param cur Cursor advanced past the block.
    /// @return cmd Decoded command identifier.
    /// @return value Decoded native value.
    /// @return input Decoded command input.
    function unpackStep(
        Cur memory cur
    ) internal pure returns (uint cmd, uint value, bytes calldata input) {
        uint abs = cur.state.position();
        uint end;
        (cmd, value, input, end) = Blocks.unpackStep(abs);
        cur.state = seekAfterBlock(cur.state, end);
    }

    /// @notice Decode and consume one RELAY block.
    /// @param cur Cursor advanced past the block.
    /// @return input Decoded relay input.
    /// @return steps Decoded remaining pipeline steps.
    function unpackRelay(
        Cur memory cur
    ) internal pure returns (bytes calldata input, bytes calldata steps) {
        uint abs = cur.state.position();
        uint end;
        (input, steps, end) = Blocks.unpackRelay(abs);
        cur.state = seekAfterBlock(cur.state, end);
    }

}
