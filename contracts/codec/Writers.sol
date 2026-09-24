// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

import {AssetAmount, AssetLiability, AccountAmount, HostAmount, Quote, Position, Tx} from "../core/Types.sol";
import {Blocks} from "./Blocks.sol";
import {Buffers} from "./Buffers.sol";
import {Sizes, Specs} from "./Specs.sol";

/// @notice Sequential block stream writer backed by a pre-allocated memory buffer.
struct Writer {
    /// @dev Packed cursor metadata. `end` is the current logical capacity.
    uint cur;
    /// @dev Destination buffer. Physical capacity may be padded up to a full 32-byte word;
    /// final length is set to the packed write position by `finish`.
    bytes dst;
}

/// @title Writers
/// @notice Response block stream builder for the rootzero protocol.
/// Initializes logical capacity from raw metadata or a block specification,
/// then lazily allocates and writes binary-encoded blocks sequentially.
/// Physical allocation is rounded up to whole 32-byte words for scratch space,
/// while the writer cursor end tracks logical capacity. Call `finish` to trim the buffer.
/// `append*` helpers consume memory inputs; `copy*` helpers consume calldata inputs.
library Writers {
    // -------------------------------------------------------------------------
    // Initialization helpers
    // -------------------------------------------------------------------------

    /// @notice Initialize writer metadata without allocating a backing buffer.
    /// @param len Initial logical byte capacity of the writer.
    /// @return writer Unallocated writer positioned at index 0.
    function init(uint len) internal pure returns (Writer memory writer) {
        writer.cur = Buffers.cursor(len);
    }

    /// @notice Initialize writer metadata for `count` blocks described by `spec`.
    /// @param spec Packed block key, payload bounds, and allocation hint.
    /// @param count Number of top-level blocks the writer is expected to encode.
    /// @return writer Unallocated writer with initial capacity derived from the specification.
    function init(uint spec, uint count) internal pure returns (Writer memory writer) {
        uint capacity = Specs.allocation(spec, count);
        writer.cur = Buffers.cursor(capacity);
    }

    // -------------------------------------------------------------------------
    // Writer state
    // -------------------------------------------------------------------------

    /// @dev Reserve through a `Writer` and update it in place.
    /// @param writer Writer whose cursor and buffer are updated.
    /// @param advance Logical number of bytes written.
    /// @param touch Number of bytes that must be addressable by the write.
    /// @return i Relative offset reserved for the write.
    function reserve(Writer memory writer, uint advance, uint touch) private pure returns (uint i) {
        (writer.cur, writer.dst, i) = Buffers.reserve(writer.cur, writer.dst, advance, touch);
    }

    /// @dev Reserve an exact number of bytes through `writer`.
    /// @param writer Writer whose cursor and buffer are updated.
    /// @param size Number of bytes to reserve and touch.
    /// @return i Relative offset reserved for the write.
    function reserve(Writer memory writer, uint size) private pure returns (uint i) {
        (writer.cur, writer.dst, i) = Buffers.reserve(writer.cur, writer.dst, size, size);
    }

    // -------------------------------------------------------------------------
    // Append helpers
    // -------------------------------------------------------------------------

    /// @notice Append an empty block.
    /// @param writer Destination writer.
    /// @param key Block key.
    function appendEmpty(Writer memory writer, bytes4 key) internal pure {
        uint i = reserve(writer, Sizes.Header);
        Blocks.writeEmpty(writer.dst, i, key);
    }

    /// @notice Append arbitrary bytes to the writer.
    /// @param writer Destination writer; `i` is advanced by `data.length`.
    /// @param data Bytes to append.
    function append(Writer memory writer, bytes memory data) internal pure {
        uint i = reserve(writer, data.length, data.length);
        bytes memory dst = writer.dst;
        // reserve validates the full physical write range.
        assembly ("memory-safe") {
            mcopy(add(add(dst, 32), i), add(data, 32), mload(data))
        }
    }

    /// @notice Append a raw 32-byte word without a block header.
    /// @param writer Destination writer; `i` is advanced by `keep`.
    /// @param value Word to append.
    /// @param keep Number of bytes to keep from the word (1..32).
    function append32(Writer memory writer, bytes32 value, uint keep) internal pure {
        uint i = reserve(writer, keep, 32);
        bytes memory dst = writer.dst;
        // reserve validates the full physical write range.
        assembly ("memory-safe") {
            mstore(add(add(dst, 32), i), value)
        }
    }

    /// @notice Append two raw 32-byte words without a block header.
    /// @param writer Destination writer; `i` is advanced by `32 + keep`.
    /// @param a First word to append.
    /// @param b Second word to append.
    /// @param keep Number of bytes to keep from the final word (1..32).
    function append64(Writer memory writer, bytes32 a, bytes32 b, uint keep) internal pure {
        uint i = reserve(writer, 32 + keep, 64);
        bytes memory dst = writer.dst;
        // reserve validates the full physical write range.
        assembly ("memory-safe") {
            let p := add(add(dst, 32), i)
            mstore(p, a)
            mstore(add(p, 32), b)
        }
    }

    /// @notice Append three raw 32-byte words without a block header.
    /// @param writer Destination writer; `i` is advanced by `64 + keep`.
    /// @param a First word to append.
    /// @param b Second word to append.
    /// @param c Third word to append.
    /// @param keep Number of bytes to keep from the final word (1..32).
    function append96(Writer memory writer, bytes32 a, bytes32 b, bytes32 c, uint keep) internal pure {
        uint i = reserve(writer, 64 + keep, 96);
        bytes memory dst = writer.dst;
        // reserve validates the full physical write range.
        assembly ("memory-safe") {
            let p := add(add(dst, 32), i)
            mstore(p, a)
            mstore(add(p, 32), b)
            mstore(add(p, 64), c)
        }
    }

    /// @notice Append a dynamic protocol block.
    /// @param writer Destination writer.
    /// @param spec Block specification used to validate and encode the payload.
    /// @param data Block payload.
    function appendBlock(Writer memory writer, uint spec, bytes memory data) internal pure {
        Specs.validate(spec, data.length);
        uint size = Sizes.Header + data.length;
        uint i = reserve(writer, size, size);
        Blocks.writeSized(writer.dst, i, Specs.key(spec), data, data.length);
    }

    /// @notice Append a custom fixed block with up to 32 payload bytes.
    /// @param writer Destination writer.
    /// @param spec Exact block specification.
    /// @param a Payload word.
    function appendBlock32(Writer memory writer, uint spec, bytes32 a) internal pure {
        uint keep = Specs.exact(spec, 1, 32);
        uint i = reserve(writer, Sizes.Header + keep, Sizes.B32);
        Blocks.write32(writer.dst, i, Specs.key(spec), a);
    }

    /// @notice Append an ACCOUNT block.
    /// @param writer Destination writer.
    /// @param account Account identifier to encode.
    function appendAccount(Writer memory writer, bytes32 account) internal pure {
        uint i = reserve(writer, Sizes.B32);
        Blocks.writeAccount(writer.dst, i, account);
    }

    /// @notice Append an ASSET block.
    /// @param writer Destination writer.
    /// @param asset Asset identifier to encode.
    function appendAsset(Writer memory writer, bytes32 asset) internal pure {
        uint i = reserve(writer, Sizes.B32);
        Blocks.writeAsset(writer.dst, i, asset);
    }

    /// @notice Append a NODE block.
    /// @param writer Destination writer.
    /// @param node Node identifier to encode.
    function appendNode(Writer memory writer, uint node) internal pure {
        uint i = reserve(writer, Sizes.B32);
        Blocks.writeNode(writer.dst, i, node);
    }

    /// @notice Append a STATUS block.
    /// @param writer Destination writer.
    /// @param code Status code to encode.
    function appendStatus(Writer memory writer, uint code) internal pure {
        uint i = reserve(writer, Sizes.B32);
        Blocks.writeStatus(writer.dst, i, code);
    }

    /// @notice Append an AMOUNT block.
    /// @param writer Destination writer.
    /// @param asset Asset identifier to encode.
    /// @param amount Asset amount to encode.
    function appendAmount(Writer memory writer, bytes32 asset, uint amount) internal pure {
        uint i = reserve(writer, Sizes.B64);
        Blocks.writeAmount(writer.dst, i, asset, amount);
    }

    /// @notice Append a structured AMOUNT value.
    /// @param writer Destination writer.
    /// @param value Structured asset amount to encode.
    function appendAmount(Writer memory writer, AssetAmount memory value) internal pure {
        appendAmount(writer, value.asset, value.amount);
    }

    /// @notice Append a BALANCE block.
    /// @param writer Destination writer.
    /// @param asset Asset identifier to encode.
    /// @param amount Balance amount to encode.
    function appendBalance(Writer memory writer, bytes32 asset, uint amount) internal pure {
        uint i = reserve(writer, Sizes.B64);
        Blocks.writeBalance(writer.dst, i, asset, amount);
    }

    /// @notice Append a structured BALANCE value.
    /// @param writer Destination writer.
    /// @param value Structured asset balance to encode.
    function appendBalance(Writer memory writer, AssetAmount memory value) internal pure {
        appendBalance(writer, value.asset, value.amount);
    }

    /// @notice Append an ASSET_LIABILITY block.
    function appendAssetLiability(Writer memory writer, bytes32 asset, bytes32 liability) internal pure {
        uint i = reserve(writer, Sizes.B64);
        Blocks.writeAssetLiability(writer.dst, i, asset, liability);
    }

    /// @notice Append a structured ASSET_LIABILITY value.
    function appendAssetLiability(Writer memory writer, AssetLiability memory value) internal pure {
        appendAssetLiability(writer, value.asset, value.liability);
    }

    /// @notice Append an ACCOUNT_ASSET block.
    /// @param writer Destination writer.
    /// @param account Account identifier to encode.
    /// @param asset Asset identifier to encode.
    function appendAccountAsset(Writer memory writer, bytes32 account, bytes32 asset) internal pure {
        uint i = reserve(writer, Sizes.B64);
        Blocks.writeAccountAsset(writer.dst, i, account, asset);
    }

    /// @notice Append a HOST_ASSET block.
    /// @param writer Destination writer.
    /// @param host Host identifier to encode.
    /// @param asset Asset identifier to encode.
    function appendHostAsset(Writer memory writer, uint host, bytes32 asset) internal pure {
        uint i = reserve(writer, Sizes.HostAsset);
        Blocks.writeHostAsset(writer.dst, i, host, asset);
    }

    /// @notice Append an ALLOCATION block.
    /// @param writer Destination writer.
    /// @param host Host identifier to encode.
    /// @param asset Asset identifier to encode.
    /// @param amount Allocation amount to encode.
    function appendAllocation(Writer memory writer, uint host, bytes32 asset, uint amount) internal pure {
        uint i = reserve(writer, Sizes.B96);
        Blocks.writeAllocation(writer.dst, i, host, asset, amount);
    }

    /// @notice Append an ALLOWANCE block.
    /// @param writer Destination writer.
    /// @param host Host identifier to encode.
    /// @param asset Asset identifier to encode.
    /// @param amount Allowance amount to encode.
    function appendAllowance(Writer memory writer, uint host, bytes32 asset, uint amount) internal pure {
        uint i = reserve(writer, Sizes.B96);
        Blocks.writeAllowance(writer.dst, i, host, asset, amount);
    }

    /// @notice Append a CUSTODY block.
    /// @param writer Destination writer.
    /// @param host Host identifier to encode.
    /// @param asset Asset identifier to encode.
    /// @param amount Custody amount to encode.
    function appendCustody(Writer memory writer, uint host, bytes32 asset, uint amount) internal pure {
        uint i = reserve(writer, Sizes.Custody);
        Blocks.writeCustody(writer.dst, i, host, asset, amount);
    }

    /// @notice Append a CUSTODY block for `host` and a structured amount.
    /// @param writer Destination writer.
    /// @param host Host identifier to encode.
    /// @param value Structured asset amount to encode.
    function appendCustody(Writer memory writer, uint host, AssetAmount memory value) internal pure {
        appendCustody(writer, host, value.asset, value.amount);
    }

    /// @notice Append a structured CUSTODY value.
    /// @param writer Destination writer.
    /// @param value Structured host asset amount to encode.
    function appendCustody(Writer memory writer, HostAmount memory value) internal pure {
        appendCustody(writer, value.host, value.asset, value.amount);
    }

    /// @notice Append an ACCOUNT_AMOUNT block.
    /// @param writer Destination writer.
    /// @param account Account identifier to encode.
    /// @param asset Asset identifier to encode.
    /// @param amount Account amount to encode.
    function appendAccountAmount(Writer memory writer, bytes32 account, bytes32 asset, uint amount) internal pure {
        uint i = reserve(writer, Sizes.B96);
        Blocks.writeAccountAmount(writer.dst, i, account, asset, amount);
    }

    /// @notice Append a structured ACCOUNT_AMOUNT value.
    /// @param writer Destination writer.
    /// @param value Structured account asset amount to encode.
    function appendAccountAmount(Writer memory writer, AccountAmount memory value) internal pure {
        appendAccountAmount(writer, value.account, value.asset, value.amount);
    }

    /// @notice Append a HOST_AMOUNT block.
    /// @param writer Destination writer.
    /// @param host Host identifier to encode.
    /// @param asset Asset identifier to encode.
    /// @param amount Host amount to encode.
    function appendHostAmount(Writer memory writer, uint host, bytes32 asset, uint amount) internal pure {
        uint i = reserve(writer, Sizes.B96);
        Blocks.writeHostAmount(writer.dst, i, host, asset, amount);
    }

    /// @notice Append a HOST_ACCOUNT_ASSET block.
    /// @param writer Destination writer.
    /// @param host Host identifier to encode.
    /// @param account Account identifier to encode.
    /// @param asset Asset identifier to encode.
    function appendHostAccountAsset(
        Writer memory writer,
        uint host,
        bytes32 account,
        bytes32 asset
    ) internal pure {
        uint i = reserve(writer, Sizes.B96);
        Blocks.writeHostAccountAsset(writer.dst, i, host, account, asset);
    }

    /// @notice Append a LIMITS block with a packed inclusive minimum and maximum.
    /// @param limits Packed inclusive minimum (high 128 bits) and maximum (low 128 bits); meaning is context-dependent.
    function appendLimits(Writer memory writer, uint limits) internal pure {
        uint i = reserve(writer, Sizes.Limits);
        Blocks.writeLimits(writer.dst, i, limits);
    }

    /// @notice Append a QUOTE with full-width asset and liability quantities.
    function appendQuote(Writer memory writer, bytes32 asset, uint amount, bytes32 liability, uint debt) internal pure {
        uint i = reserve(writer, Sizes.Quote);
        Blocks.writeQuote(writer.dst, i, asset, amount, liability, debt);
    }

    /// @notice Append a structured QUOTE.
    function appendQuote(Writer memory writer, Quote memory quote) internal pure {
        appendQuote(writer, quote.asset, quote.amount, quote.liability, quote.debt);
    }

    /// @notice Append a POSITION block.
    function appendPosition(
        Writer memory writer,
        bytes32 asset,
        uint amount,
        bytes32 liability,
        uint debt,
        bytes32 counterparty
    ) internal pure {
        uint i = reserve(writer, Sizes.Position);
        Blocks.writePosition(writer.dst, i, asset, amount, liability, debt, counterparty);
    }

    /// @notice Append a structured POSITION value.
    function appendPosition(Writer memory writer, Position memory value) internal pure {
        appendPosition(writer, value.asset, value.amount, value.liability, value.debt, value.counterparty);
    }

    /// @notice Append a TRANSACTION block.
    /// @param writer Destination writer.
    /// @param from Debit account identifier.
    /// @param to Credit account identifier.
    /// @param asset Asset identifier to encode.
    /// @param amount Transaction amount to encode.
    function appendTransaction(
        Writer memory writer,
        bytes32 from,
        bytes32 to,
        bytes32 asset,
        uint amount
    ) internal pure {
        uint i = reserve(writer, Sizes.B128);
        Blocks.writeTransaction(writer.dst, i, from, to, asset, amount);
    }

    /// @notice Append a structured TRANSACTION value.
    /// @param writer Destination writer.
    /// @param value Structured transaction to encode.
    function appendTransaction(Writer memory writer, Tx memory value) internal pure {
        appendTransaction(writer, value.from, value.to, value.asset, value.amount);
    }

    /// @notice Append a HOST_ACCOUNT_AMOUNT block.
    /// @param writer Destination writer.
    /// @param host Host identifier to encode.
    /// @param account Account identifier to encode.
    /// @param asset Asset identifier to encode.
    /// @param amount Host account amount to encode.
    function appendHostAccountAmount(
        Writer memory writer,
        uint host,
        bytes32 account,
        bytes32 asset,
        uint amount
    ) internal pure {
        uint i = reserve(writer, Sizes.B128);
        Blocks.writeHostAccountAmount(writer.dst, i, host, account, asset, amount);
    }

    /// @notice Append a LIST block.
    /// @param writer Destination writer.
    /// @param value Encoded list payload.
    function appendList(Writer memory writer, bytes memory value) internal pure {
        uint size = Sizes.Header + value.length;
        uint i = reserve(writer, size);
        Blocks.writeList(writer.dst, i, value);
    }

    /// @notice Append a BYTES block.
    /// @param writer Destination writer.
    /// @param value Byte payload to encode.
    function appendBytes(Writer memory writer, bytes memory value) internal pure {
        uint size = Sizes.Header + value.length;
        uint i = reserve(writer, size);
        Blocks.writeBytes(writer.dst, i, value);
    }

    /// @notice Append a STRING block.
    /// @param writer Destination writer.
    /// @param value String payload to encode.
    function appendString(Writer memory writer, string memory value) internal pure {
        uint size = Sizes.Header + bytes(value).length;
        uint i = reserve(writer, size);
        Blocks.writeString(writer.dst, i, value);
    }

    /// @notice Append a STEP block.
    /// @param writer Destination writer.
    /// @param cmd Command identifier to encode.
    /// @param value Native value to encode.
    /// @param input Command input to encode.
    function appendStep(Writer memory writer, uint cmd, uint value, bytes memory input) internal pure {
        uint size = Sizes.Step + input.length;
        uint i = reserve(writer, size);
        Blocks.writeCompositeSized(writer.dst, i, bytes4(uint32(Specs.Step >> 224)), cmd, value, input, size);
    }

    /// @notice Append a CALL block.
    /// @param writer Destination writer.
    /// @param target Call target to encode.
    /// @param resources Packed resources to encode.
    /// @param payload Call payload to encode.
    function appendCall(Writer memory writer, uint target, uint resources, bytes memory payload) internal pure {
        uint size = Sizes.B64 + Sizes.Header + payload.length;
        uint i = reserve(writer, size);
        Blocks.writeCompositeSized(writer.dst, i, bytes4(uint32(Specs.Call >> 224)), target, resources, payload, size);
    }

    /// @notice Append a RELAY block.
    /// @param writer Destination writer.
    /// @param input Relay input to encode.
    /// @param steps Remaining steps to encode.
    function appendRelay(Writer memory writer, bytes memory input, bytes memory steps) internal pure {
        uint size = 3 * Sizes.Header + input.length + steps.length;
        uint i = reserve(writer, size);
        Blocks.writeRelaySized(writer.dst, i, input, steps, size);
    }

    /// @notice Append a DISPATCH block.
    /// @param writer Destination writer.
    /// @param portal Destination portal to encode.
    /// @param resources Packed resources to encode.
    /// @param payload Dispatch payload to encode.
    function appendDispatch(Writer memory writer, uint portal, uint resources, bytes memory payload) internal pure {
        uint size = Sizes.B64 + Sizes.Header + payload.length;
        uint i = reserve(writer, size);
        Blocks.writeCompositeSized(writer.dst, i, bytes4(uint32(Specs.Dispatch >> 224)), portal, resources, payload, size);
    }

    /// @notice Append a CONTEXT block.
    /// @param writer Destination writer.
    /// @param account Account identifier to encode.
    /// @param state State payload to encode.
    /// @param input Input payload to encode.
    function appendContext(
        Writer memory writer,
        bytes32 account,
        bytes memory state,
        bytes memory input
    ) internal pure {
        uint size = Sizes.B32 + 2 * Sizes.Header + state.length + input.length;
        uint i = reserve(writer, size);
        Blocks.writeContextSized(writer.dst, i, account, state, input, size);
    }

    /// @notice Append a RECOVER block.
    /// @param writer Destination writer.
    /// @param handler Recovery handler to encode.
    /// @param resources Packed resources to encode.
    /// @param recoverykey Recovery key to encode.
    /// @param witness Recovery witness to encode.
    function appendRecover(
        Writer memory writer,
        uint handler,
        uint resources,
        bytes32 recoverykey,
        bytes memory witness
    ) internal pure {
        uint size = Sizes.B96 + Sizes.Header + witness.length;
        uint i = reserve(writer, size);
        Blocks.writeRecoverSized(writer.dst, i, handler, resources, recoverykey, witness, size);
    }

    /// @notice Append a LABEL block.
    /// @param writer Destination writer.
    /// @param namespace Label namespace to encode.
    /// @param name Label text to encode.
    function appendLabel(
        Writer memory writer,
        bytes32 namespace,
        string memory name
    ) internal pure {
        uint size = Sizes.B32 + Sizes.Header + bytes(name).length;
        uint i = reserve(writer, size);
        Blocks.writeLabelSized(writer.dst, i, namespace, name, size);
    }

    /// @notice Append a SCHEMA block.
    /// @param writer Destination writer.
    /// @param spec Block specification to encode.
    /// @param body Schema DSL string, optionally prefixed with `name:`.
    function appendSchema(Writer memory writer, uint spec, string memory body) internal pure {
        uint size = Sizes.B32 + Sizes.Header + bytes(body).length;
        uint i = reserve(writer, size);
        Blocks.writeSchemaSized(writer.dst, i, spec, body, size);
    }

    // -------------------------------------------------------------------------
    // Calldata copy helpers
    // -------------------------------------------------------------------------

    /// @notice Append arbitrary calldata bytes to the writer.
    /// @param writer Destination writer; `i` is advanced by `data.length`.
    /// @param data Calldata bytes to append.
    function copy(Writer memory writer, bytes calldata data) internal pure {
        uint i = reserve(writer, data.length, data.length);
        bytes memory dst = writer.dst;
        // reserve validates the full physical write range.
        assembly ("memory-safe") {
            calldatacopy(add(add(dst, 32), i), data.offset, data.length)
        }
    }

    /// @notice Append a custom block by copying its payload from calldata.
    function copyBlock(Writer memory writer, uint spec, bytes calldata data) internal pure {
        Specs.validate(spec, data.length);
        uint size = Sizes.Header + data.length;
        uint i = reserve(writer, size);
        Blocks.copySized(writer.dst, i, Specs.key(spec), data, data.length);
    }

    /// @notice Append a LIST block by copying its payload from calldata.
    function copyList(Writer memory writer, bytes calldata value) internal pure {
        uint size = Sizes.Header + value.length;
        uint i = reserve(writer, size);
        Blocks.copySized(writer.dst, i, bytes4(uint32(Specs.List >> 224)), value, value.length);
    }

    /// @notice Append a BYTES block by copying its payload from calldata.
    function copyBytes(Writer memory writer, bytes calldata value) internal pure {
        uint size = Sizes.Header + value.length;
        uint i = reserve(writer, size);
        Blocks.copySized(writer.dst, i, bytes4(uint32(Specs.Bytes >> 224)), value, value.length);
    }

    /// @notice Append a STRING block by copying its payload from calldata.
    function copyString(Writer memory writer, string calldata value) internal pure {
        uint size = Sizes.Header + bytes(value).length;
        uint i = reserve(writer, size);
        Blocks.copySized(writer.dst, i, bytes4(uint32(Specs.String >> 224)), bytes(value), bytes(value).length);
    }

    /// @notice Append a STEP block by copying its nested input from calldata.
    function copyStep(Writer memory writer, uint cmd, uint value, bytes calldata input) internal pure {
        uint size = Sizes.Step + input.length;
        uint i = reserve(writer, size);
        Blocks.copyCompositeSized(writer.dst, i, bytes4(uint32(Specs.Step >> 224)), cmd, value, input, size);
    }

    /// @notice Append a CALL block by copying its nested payload from calldata.
    function copyCall(Writer memory writer, uint target, uint resources, bytes calldata payload) internal pure {
        uint size = Sizes.B64 + Sizes.Header + payload.length;
        uint i = reserve(writer, size);
        Blocks.copyCompositeSized(writer.dst, i, bytes4(uint32(Specs.Call >> 224)), target, resources, payload, size);
    }

    /// @notice Append a RELAY block by copying its nested streams from calldata.
    function copyRelay(Writer memory writer, bytes calldata input, bytes calldata steps) internal pure {
        uint size = 3 * Sizes.Header + input.length + steps.length;
        uint i = reserve(writer, size);
        Blocks.copyRelaySized(writer.dst, i, input, steps, size);
    }

    /// @notice Append a DISPATCH block by copying its nested payload from calldata.
    function copyDispatch(Writer memory writer, uint portal, uint resources, bytes calldata payload) internal pure {
        uint size = Sizes.B64 + Sizes.Header + payload.length;
        uint i = reserve(writer, size);
        Blocks.copyCompositeSized(writer.dst, i, bytes4(uint32(Specs.Dispatch >> 224)), portal, resources, payload, size);
    }

    /// @notice Append a CONTEXT block by copying its nested streams from calldata.
    function copyContext(
        Writer memory writer,
        bytes32 account,
        bytes calldata state,
        bytes calldata input
    ) internal pure {
        uint size = Sizes.B32 + 2 * Sizes.Header + state.length + input.length;
        uint i = reserve(writer, size);
        Blocks.copyContextSized(writer.dst, i, account, state, input, size);
    }

    /// @notice Append a RECOVER block by copying its nested witness from calldata.
    function copyRecover(
        Writer memory writer,
        uint handler,
        uint resources,
        bytes32 recoverykey,
        bytes calldata witness
    ) internal pure {
        uint size = Sizes.B96 + Sizes.Header + witness.length;
        uint i = reserve(writer, size);
        Blocks.copyRecoverSized(writer.dst, i, handler, resources, recoverykey, witness, size);
    }

    // -------------------------------------------------------------------------
    // Finalisation
    // -------------------------------------------------------------------------

    /// @notice Return an empty buffer when unused, otherwise trim `dst` to the bytes written.
    /// Sets the `bytes` length slot in memory to the packed write position without copying.
    /// @param writer Completed writer.
    /// @return out The written block stream; length equals the packed write position.
    function finish(Writer memory writer) internal pure returns (bytes memory out) {
        out = Buffers.finish(writer.cur, writer.dst);
    }
}
