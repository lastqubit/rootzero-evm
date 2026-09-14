// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

import {Keys} from "./Keys.sol";
import {Sizes, Specs, Headers} from "./Specs.sol";
import {max32} from "../utils/Utils.sol";
import {Position} from "../core/Types.sol";
import {OutOfRange, UnexpectedValue} from "../utils/Errors.sol";

/// @title Blocks
/// @notice Stateless helpers for inspecting and encoding protocol blocks.
/// @dev Blocks use `[key:4][payload length:4][payload]`. Calldata helpers use
/// absolute positions. Bounded navigation helpers also take an absolute `end`;
/// specialized absolute readers and unpackers intentionally omit logical-region
/// checks. Their caller must validate consumed positions through a surrounding
/// cursor, execution, or equivalent boundary.
/// Full-header comparisons use right-aligned uint64 values. Readers that need
/// individual fields extract the key and length directly from the calldata word.
/// Encoded write words and specs remain uint256.
///
/// Fixed-width unpackers return decoded fields only because their following
/// position is statically `abs + Sizes.X`. Dynamic leaf and composite unpackers
/// return absolute `end` last because their encoded size is known only while
/// decoding. Built-in composites use optimized assembly for fixed fields and
/// semantic unpackers for child blocks. Custom schema decoders should favor
/// `expect`, readable calldata slices, semantic child unpackers, and a final
/// equality check proving that the children consume the complete payload.
///
/// Generic and specialized writers are unchecked: callers must validate inputs
/// and reserve the complete destination region before calling them. Helpers are
/// ordered as inspection, generic writes, specialized writes, decoding, and
/// block factories; fixed layouts within a section are ordered from smaller to
/// larger payloads. `write*` helpers copy dynamic inputs from memory, while
/// `copy*` helpers copy dynamic inputs directly from calldata. Allocating
/// factories use the semantic block name for memory inputs and append `Copy`
/// for calldata inputs. Factories reuse validated lengths in private writers
/// where delegating to standalone writers would repeat length calculations.
library Blocks {
    /// @dev A block header or declared payload exceeds the source region.
    error MalformedBlocks();
    /// @dev A block key or payload size does not match its expected shape.
    error InvalidBlock();
    /// @dev A scoped block run contained no blocks.
    error EmptyRun();

    // -------------------------------------------------------------------------
    // Calldata inspection and navigation
    // -------------------------------------------------------------------------

    /// @notice Decode a block header at an absolute calldata position.
    /// @dev DANGER: This performs an unchecked calldata read and does not ensure the
    /// complete header or payload lies within a logical calldata region.
    /// @param abs Absolute calldata position of the header.
    /// @return key Decoded block key.
    /// @return len Decoded payload length.
    function header(uint abs) internal pure returns (bytes4 key, uint len) {
        assembly ("memory-safe") {
            let word := calldataload(abs)
            key := and(word, 0xffffffff00000000000000000000000000000000000000000000000000000000)
            len := and(shr(192, word), 0xffffffff)
        }
    }

    /// @notice Decode a block header and validate its key at an absolute calldata position.
    /// @dev DANGER: This performs an unchecked calldata read and does not ensure the
    /// complete header or payload lies within a logical calldata region.
    /// @param abs Absolute calldata position of the header.
    /// @param expected Expected block key.
    /// @return len Decoded payload length.
    function header(uint abs, bytes4 expected) internal pure returns (uint len) {
        uint key;
        assembly ("memory-safe") {
            let word := calldataload(abs)
            key := shr(224, word)
            len := and(shr(192, word), 0xffffffff)
        }
        if (key != uint32(expected)) revert InvalidBlock();
    }

    /// @notice Decode a complete block header within an absolute calldata region.
    /// @param abs Absolute position of the header.
    /// @param end Absolute region boundary.
    /// @return key Decoded block key.
    /// @return len Decoded payload length.
    function peek(uint abs, uint end) internal pure returns (bytes4 key, uint len) {
        if (abs > end) revert MalformedBlocks();
        unchecked {
            uint remaining = end - abs;
            if (remaining < Sizes.Header) revert MalformedBlocks();
            (key, len) = header(abs);
            if (len > remaining - Sizes.Header) revert MalformedBlocks();
        }
    }

    /// @notice Validate and enter a block at the start of a calldata slice.
    /// @dev DANGER: This extracts the slice's absolute base but does not prove
    /// that the header or declared payload lies within the slice. The caller
    /// must validate the returned bounds against `source.length`.
    /// @param source Calldata slice beginning with the expected block.
    /// @param spec Expected block specification.
    /// @return body Absolute position of the first payload byte.
    /// @return end Absolute position immediately after the payload.
    /// @return limit Absolute position immediately after the calldata slice.
    function enter(bytes calldata source, uint spec) internal pure returns (uint body, uint end, uint limit) {
        uint abs;
        assembly ("memory-safe") {
            abs := source.offset
            limit := add(abs, source.length)
        }
        (body, end) = enter(abs, spec);
    }

    /// @notice Validate that a calldata slice is exactly one matching block.
    /// @dev The specification may accept a payload-size range; exactness means
    /// that the decoded block occupies the complete calldata slice.
    /// @param source Complete calldata slice occupied by the expected block.
    /// @param spec Expected block specification.
    /// @return body Absolute position of the first payload byte.
    function exact(bytes calldata source, uint spec) internal pure returns (uint body) {
        uint end;
        uint limit;
        (body, end, limit) = enter(source, spec);
        if (end != limit) revert InvalidBlock();
    }

    /// @notice Validate and enter a block at an absolute calldata position.
    /// @dev DANGER: This performs an unchecked calldata read and does not ensure `end`
    /// lies within the caller's logical calldata region. Only the key, minimum,
    /// and maximum fields of `spec` are used.
    /// @param abs Absolute calldata position of the header.
    /// @param spec Expected block specification.
    /// @return body Absolute position of the first payload byte.
    /// @return end Absolute position immediately after the payload.
    function enter(uint abs, uint spec) internal pure returns (uint body, uint end) {
        uint key;
        uint len;
        assembly ("memory-safe") {
            let word := calldataload(abs)
            key := shr(224, word)
            len := and(shr(192, word), 0xffffffff)
        }
        uint max = uint32(spec >> 160);
        if (key != uint32(spec >> 224) || len < uint32(spec >> 192) || (max != 0 && len > max))
            revert InvalidBlock();

        unchecked {
            body = abs + Sizes.Header;
            end = body + len;
        }
    }

    /// @notice Validate a block specification and enter after a fixed payload prefix.
    /// @dev DANGER: This performs an unchecked calldata read and does not ensure
    /// that the returned positions lie within the caller's logical calldata region.
    /// @param abs Absolute calldata position of the header.
    /// @param spec Expected block specification.
    /// @param amount Number of initial payload bytes to advance over.
    /// @return body Absolute position of the first payload byte.
    /// @return next Absolute payload position after the fixed prefix.
    /// @return end Absolute position immediately after the payload.
    function enter(uint abs, uint spec, uint amount) internal pure returns (uint body, uint next, uint end) {
        (body, end) = enter(abs, spec);
        if (amount > end - body) revert InvalidBlock();
        unchecked {
            next = body + amount;
        }
    }

    /// @notice Validate a known block key and return its payload bounds.
    /// @dev DANGER: This performs an unchecked calldata read and validates only
    /// the key. The caller must validate the known payload shape and returned end.
    /// @param abs Absolute calldata position of the header.
    /// @param key Expected block key.
    /// @return body Absolute position of the first payload byte.
    /// @return end Absolute position immediately after the payload.
    function enter(uint abs, bytes4 key) internal pure returns (uint body, uint end) {
        uint actual;
        uint len;
        assembly ("memory-safe") {
            let word := calldataload(abs)
            actual := shr(224, word)
            len := and(shr(192, word), 0xffffffff)
        }
        if (actual != uint32(key)) revert InvalidBlock();
        unchecked {
            body = abs + Sizes.Header;
            end = body + len;
        }
    }

    /// @notice Validate a block key and enter after a fixed payload prefix.
    /// @dev DANGER: This performs an unchecked calldata read, validates no
    /// payload-size constraint, and does not ensure the returned positions lie
    /// within the caller's logical calldata region.
    /// @param abs Absolute calldata position of the header.
    /// @param key Expected block key.
    /// @param amount Number of initial payload bytes to advance over.
    /// @return body Absolute position of the first payload byte.
    /// @return next Absolute payload position after the fixed prefix.
    /// @return end Absolute position immediately after the payload.
    function enter(uint abs, bytes4 key, uint amount) internal pure returns (uint body, uint next, uint end) {
        (body, end) = enter(abs, key);
        if (amount > end - body) revert InvalidBlock();
        unchecked {
            next = body + amount;
        }
    }

    /// @dev Validate the key and exact payload size of a fixed-width block.
    /// @param abs Absolute calldata position of the header.
    /// @param key Expected block key.
    /// @param size Expected payload length.
    /// @return body Absolute position of the payload.
    /// @return end Absolute position after the payload.
    function expectFixed(uint abs, bytes4 key, uint size) private pure returns (uint body, uint end) {
        uint64 actual;
        assembly ("memory-safe") {
            actual := shr(192, calldataload(abs))
        }
        uint64 expected = (uint64(uint32(key)) << 32) | uint64(size);
        if (actual != expected) revert InvalidBlock();
        unchecked {
            body = abs + Sizes.Header;
            end = body + size;
        }
    }

    /// @notice Validate an empty block at an absolute calldata position.
    /// @dev DANGER: This performs an unchecked calldata read. The caller must
    /// validate the returned end against its logical calldata region.
    /// @param abs Absolute position of the block header.
    /// @param key Expected block key.
    /// @return end Absolute position immediately after the empty block header.
    function expectEmpty(uint abs, bytes4 key) internal pure returns (uint end) {
        uint64 actual;
        assembly ("memory-safe") {
            actual := shr(192, calldataload(abs))
        }
        uint64 expected = uint64(uint32(key)) << 32;
        if (actual != expected) revert InvalidBlock();
        return abs + Sizes.Header;
    }

    /// @notice Return whether `abs` identifies a header with `key` before an absolute end.
    /// @param abs Absolute calldata position to inspect.
    /// @param end Absolute region boundary.
    /// @param key Expected block key.
    /// @return Whether a complete matching header exists.
    function hasAt(uint abs, uint end, bytes4 key) internal pure returns (bool) {
        // Short-circuiting proves the subtraction cannot underflow.
        unchecked {
            if (abs > end || Sizes.Header > end - abs) return false;
        }
        return bytes4(read32(abs)) == key;
    }

    /// @notice Return whether `abs` identifies a complete empty block header.
    /// @param abs Absolute position to inspect.
    /// @param end Absolute region boundary.
    /// @param key Expected block key.
    /// @return Whether the expected key occurs with a zero-length payload.
    function isEmpty(uint abs, uint end, bytes4 key) internal pure returns (bool) {
        unchecked {
            if (abs > end || Sizes.Header > end - abs) return false;
        }
        uint64 head = uint64(uint(read32(abs)) >> 192);
        return head == uint64(uint32(key)) << 32;
    }

    /// @notice Find the first block with `key` at or after absolute position `abs`.
    /// @param abs Absolute search position.
    /// @param end Absolute region boundary.
    /// @param key Block key to find.
    /// @return Absolute position of the matching block, or `end` when absent.
    function find(uint abs, uint end, bytes4 key) internal pure returns (uint) {
        while (abs < end) {
            (bytes4 current, uint len) = header(abs);
            // len is uint32; the loop and region check prove these operations safe.
            unchecked {
                uint size = Sizes.Header + len;
                if (size > end - abs) revert MalformedBlocks();
                if (current == key) return abs;
                abs += size;
            }
        }
        return end;
    }

    /// @notice Count consecutive blocks with `key` from absolute position `abs`.
    /// @param abs Absolute start position.
    /// @param limit Absolute region boundary.
    /// @param key Block key forming the run.
    /// @return total Number of consecutive matching blocks.
    /// @return end Absolute position after the run.
    function run(uint abs, uint limit, bytes4 key) internal pure returns (uint total, uint end) {
        end = abs;
        while (end < limit) {
            (bytes4 current, uint len) = header(end);
            // Validate before testing the key, including a malformed nonmatching block.
            unchecked {
                uint size = Sizes.Header + len;
                if (size > limit - end) revert MalformedBlocks();
                if (current != key) break;
                end += size;
                ++total;
            }
        }
    }

    /// @notice Count consecutive blocks with `key` using a minimal hint-only scan.
    /// @dev DANGER: This is not validation. It stops on a different key or when the
    /// next declared block end exceeds `limit`; malformed or trailing data does not
    /// revert. Use only for optional allocation hints whose result is later validated
    /// by normal decoding and execution finalization.
    /// @param abs Absolute start position.
    /// @param limit Absolute region boundary.
    /// @param key Block key forming the run.
    /// @return total Number of complete consecutive matching blocks.
    function runCount(uint abs, uint limit, bytes4 key) internal pure returns (uint total) {
        uint expected = uint32(key);
        assembly ("memory-safe") {
            for {} lt(abs, limit) {} {
                let word := calldataload(abs)
                let actual := shr(224, word)
                if iszero(eq(actual, expected)) {
                    break
                }

                let len := and(shr(192, word), 0xffffffff)
                let next := add(add(abs, 8), len)
                if gt(next, limit) {
                    break
                }

                abs := next
                total := add(total, 1)
            }
        }
    }

    /// @notice Count a run that must consume the complete region.
    /// @dev Reverts when any well-formed trailing block has a different key.
    /// @param abs Absolute start position.
    /// @param limit Absolute region boundary.
    /// @param key Required block key for the complete region.
    /// @return total Number of matching blocks.
    /// @return end Absolute position equal to `limit`.
    function runExact(uint abs, uint limit, bytes4 key) internal pure returns (uint total, uint end) {
        (total, end) = run(abs, limit, key);
        if (end != limit) revert InvalidBlock();
    }

    // Generic block writes

    /// @notice Write an empty block header at `i`.
    /// @dev DANGER: Unchecked memory write. Reserve `Sizes.Header` bytes first.
    /// @param dst Destination buffer.
    /// @param i Relative write position.
    /// @param key Block key.
    function writeEmpty(bytes memory dst, uint i, bytes4 key) internal pure {
        uint word = uint(uint32(key)) << 224;
        assembly ("memory-safe") {
            mstore(add(add(dst, 0x20), i), word)
        }
    }

    /// @notice Write a custom block with one payload word at `i`.
    /// @dev DANGER: Unchecked memory write. Reserve `Sizes.B32` bytes first.
    /// @param dst Destination buffer.
    /// @param i Relative write position.
    /// @param key Block key.
    /// @param a Payload word.
    function write32(bytes memory dst, uint i, bytes4 key, bytes32 a) internal pure {
        uint word = (uint(uint32(key)) << 224) | (uint(32) << 192);
        assembly ("memory-safe") {
            let p := add(add(dst, 0x20), i)
            mstore(p, word)
            mstore(add(p, 0x08), a)
        }
    }

    /// @notice Write a custom block with two payload words at `i`.
    /// @dev DANGER: Unchecked memory write. Reserve `Sizes.B64` bytes first.
    /// @param dst Destination buffer.
    /// @param i Relative write position.
    /// @param key Block key.
    /// @param a First payload word.
    /// @param b Second payload word.
    function write64(bytes memory dst, uint i, bytes4 key, bytes32 a, bytes32 b) internal pure {
        uint word = (uint(uint32(key)) << 224) | (uint(64) << 192);
        assembly ("memory-safe") {
            let p := add(add(dst, 0x20), i)
            mstore(p, word)
            mstore(add(p, 0x08), a)
            mstore(add(p, 0x28), b)
        }
    }

    /// @notice Write a custom block with three payload words at `i`.
    /// @dev DANGER: Unchecked memory write. Reserve `Sizes.B96` bytes first.
    /// @param dst Destination buffer.
    /// @param i Relative write position.
    /// @param key Block key.
    /// @param a First payload word.
    /// @param b Second payload word.
    /// @param c Third payload word.
    function write96(bytes memory dst, uint i, bytes4 key, bytes32 a, bytes32 b, bytes32 c) internal pure {
        uint word = (uint(uint32(key)) << 224) | (uint(96) << 192);
        assembly ("memory-safe") {
            let p := add(add(dst, 0x20), i)
            mstore(p, word)
            mstore(add(p, 0x08), a)
            mstore(add(p, 0x28), b)
            mstore(add(p, 0x48), c)
        }
    }

    /// @notice Write a custom block with a dynamic payload at `i`.
    /// @dev DANGER: Unchecked memory write. The caller must validate the payload
    /// length and reserve `Sizes.Header + payload.length` bytes first.
    /// @param dst Destination buffer.
    /// @param i Relative write position.
    /// @param key Block key.
    /// @param payload Block payload.
    function write(bytes memory dst, uint i, bytes4 key, bytes memory payload) internal pure {
        uint len = max32(payload.length);
        uint word = (uint(uint32(key)) << 224) | (len << 192);
        assembly ("memory-safe") {
            let p := add(add(dst, 0x20), i)
            mstore(p, word)
            mcopy(add(p, 0x08), add(payload, 0x20), len)
        }
    }

    /// @dev DANGER: len must equal payload.length and fit uint32. The caller must
    /// reserve the complete header/payload and trailing header scratch space.
    /// The standalone writer stays direct to avoid extra helper-call overhead.
    function writeSized(bytes memory dst, uint i, bytes4 key, bytes memory payload, uint len) internal pure {
        uint word = (uint(uint32(key)) << 224) | (len << 192);
        assembly ("memory-safe") {
            let p := add(add(dst, 0x20), i)
            mstore(p, word)
            mcopy(add(p, 0x08), add(payload, 0x20), len)
        }
    }

    // Fixed-width block writes

    // One-word payloads

    /// @notice Write an ACCOUNT block at `i`.
    /// @dev DANGER: Unchecked memory write. Reserve `Sizes.B32` bytes first.
    /// @param dst Destination buffer.
    /// @param i Relative write position.
    /// @param account Account identifier to encode.
    function writeAccount(bytes memory dst, uint i, bytes32 account) internal pure {
        uint spec = Specs.Account;
        assembly ("memory-safe") {
            let p := add(add(dst, 0x20), i)
            mstore(p, spec)
            mstore(add(p, 0x08), account)
        }
    }

    /// @notice Write an ASSET block at `i`.
    /// @dev DANGER: Unchecked memory write. Reserve `Sizes.B32` bytes first.
    /// @param dst Destination buffer.
    /// @param i Relative write position.
    /// @param asset Asset identifier to encode.
    function writeAsset(bytes memory dst, uint i, bytes32 asset) internal pure {
        uint spec = Specs.Asset;
        assembly ("memory-safe") {
            let p := add(add(dst, 0x20), i)
            mstore(p, spec)
            mstore(add(p, 0x08), asset)
        }
    }

    /// @notice Write a NODE block at `i`.
    /// @dev DANGER: Unchecked memory write. Reserve `Sizes.B32` bytes first.
    /// @param dst Destination buffer.
    /// @param i Relative write position.
    /// @param node Node identifier to encode.
    function writeNode(bytes memory dst, uint i, uint node) internal pure {
        uint spec = Specs.Node;
        assembly ("memory-safe") {
            let p := add(add(dst, 0x20), i)
            mstore(p, spec)
            mstore(add(p, 0x08), node)
        }
    }

    /// @notice Write a STATUS block at `i`.
    /// @dev DANGER: Unchecked memory write. Reserve `Sizes.B32` bytes first.
    /// @param dst Destination buffer.
    /// @param i Relative write position.
    /// @param code Status code to encode.
    function writeStatus(bytes memory dst, uint i, uint code) internal pure {
        uint spec = Specs.Status;
        assembly ("memory-safe") {
            let p := add(add(dst, 0x20), i)
            mstore(p, spec)
            mstore(add(p, 0x08), code)
        }
    }

    // Two-word payloads

    /// @notice Write an AMOUNT block at `i`.
    /// @dev DANGER: Unchecked memory write. Reserve `Sizes.B64` bytes first.
    /// @param dst Destination buffer.
    /// @param i Relative write position.
    /// @param asset Asset identifier to encode.
    /// @param amount Asset amount to encode.
    function writeAmount(bytes memory dst, uint i, bytes32 asset, uint amount) internal pure {
        uint spec = Specs.Amount;
        assembly ("memory-safe") {
            let p := add(add(dst, 0x20), i)
            mstore(p, spec)
            mstore(add(p, 0x08), asset)
            mstore(add(p, 0x28), amount)
        }
    }

    /// @notice Write a BALANCE block at `i`.
    /// @dev DANGER: Unchecked memory write. Reserve `Sizes.B64` bytes first.
    /// @param dst Destination buffer.
    /// @param i Relative write position.
    /// @param asset Asset identifier to encode.
    /// @param amount Balance amount to encode.
    function writeBalance(bytes memory dst, uint i, bytes32 asset, uint amount) internal pure {
        uint spec = Specs.Balance;
        assembly ("memory-safe") {
            let p := add(add(dst, 0x20), i)
            mstore(p, spec)
            mstore(add(p, 0x08), asset)
            mstore(add(p, 0x28), amount)
        }
    }

    /// @notice Write an ASSET_LIABILITY block at `i`.
    /// @dev DANGER: Unchecked memory write. Reserve `Sizes.B64` bytes first.
    /// @param dst Destination buffer.
    /// @param i Relative write position.
    /// @param asset Asset identifier to encode.
    /// @param liability Liability identifier to encode.
    function writeAssetLiability(bytes memory dst, uint i, bytes32 asset, bytes32 liability) internal pure {
        uint spec = Specs.AssetLiability;
        assembly ("memory-safe") {
            let p := add(add(dst, 0x20), i)
            mstore(p, spec)
            mstore(add(p, 0x08), asset)
            mstore(add(p, 0x28), liability)
        }
    }

    /// @notice Write an ACCOUNT_ASSET block at `i`.
    /// @dev DANGER: Unchecked memory write. Reserve `Sizes.B64` bytes first.
    /// @param dst Destination buffer.
    /// @param i Relative write position.
    /// @param account Account identifier to encode.
    /// @param asset Asset identifier to encode.
    function writeAccountAsset(bytes memory dst, uint i, bytes32 account, bytes32 asset) internal pure {
        uint spec = Specs.AccountAsset;
        assembly ("memory-safe") {
            let p := add(add(dst, 0x20), i)
            mstore(p, spec)
            mstore(add(p, 0x08), account)
            mstore(add(p, 0x28), asset)
        }
    }

    /// @notice Write a HOST_ASSET block at `i`.
    /// @dev DANGER: Unchecked memory write. Reserve `Sizes.B64` bytes first.
    /// @param dst Destination buffer.
    /// @param i Relative write position.
    /// @param host Host identifier to encode.
    /// @param asset Asset identifier to encode.
    function writeHostAsset(bytes memory dst, uint i, uint host, bytes32 asset) internal pure {
        uint spec = Specs.HostAsset;
        assembly ("memory-safe") {
            let p := add(add(dst, 0x20), i)
            mstore(p, spec)
            mstore(add(p, 0x08), host)
            mstore(add(p, 0x28), asset)
        }
    }

    // Three-word payloads

    /// @notice Write a BOOTSTRAP block at `i`.
    /// @dev DANGER: Unchecked memory write. Reserve `Sizes.Bootstrap` bytes first.
    /// @param dst Destination buffer.
    /// @param i Relative write position.
    /// @param asset Asset identifier to bootstrap.
    /// @param amount Balance amount to source.
    /// @param budget Native-value budget to source.
    function writeBootstrap(bytes memory dst, uint i, bytes32 asset, uint amount, uint budget) internal pure {
        uint spec = Specs.Bootstrap;
        assembly ("memory-safe") {
            let p := add(add(dst, 0x20), i)
            mstore(p, spec)
            mstore(add(p, 0x08), asset)
            mstore(add(p, 0x28), amount)
            mstore(add(p, 0x48), budget)
        }
    }

    /// @notice Write an ALLOCATION block at `i`.
    /// @dev DANGER: Unchecked memory write. Reserve `Sizes.B96` bytes first.
    /// @param dst Destination buffer.
    /// @param i Relative write position.
    /// @param host Host identifier to encode.
    /// @param asset Asset identifier to encode.
    /// @param amount Allocation amount to encode.
    function writeAllocation(bytes memory dst, uint i, uint host, bytes32 asset, uint amount) internal pure {
        uint spec = Specs.Allocation;
        assembly ("memory-safe") {
            let p := add(add(dst, 0x20), i)
            mstore(p, spec)
            mstore(add(p, 0x08), host)
            mstore(add(p, 0x28), asset)
            mstore(add(p, 0x48), amount)
        }
    }

    /// @notice Write an ALLOWANCE block at `i`.
    /// @dev DANGER: Unchecked memory write. Reserve `Sizes.B96` bytes first.
    /// @param dst Destination buffer.
    /// @param i Relative write position.
    /// @param host Host identifier to encode.
    /// @param asset Asset identifier to encode.
    /// @param amount Allowance amount to encode.
    function writeAllowance(bytes memory dst, uint i, uint host, bytes32 asset, uint amount) internal pure {
        uint spec = Specs.Allowance;
        assembly ("memory-safe") {
            let p := add(add(dst, 0x20), i)
            mstore(p, spec)
            mstore(add(p, 0x08), host)
            mstore(add(p, 0x28), asset)
            mstore(add(p, 0x48), amount)
        }
    }

    /// @notice Write a CUSTODY block at `i`.
    /// @dev DANGER: Unchecked memory write. Reserve `Sizes.Custody` bytes first.
    /// @param dst Destination buffer.
    /// @param i Relative write position.
    /// @param host Host identifier to encode.
    /// @param asset Asset identifier to encode.
    /// @param amount Custody amount to encode.
    function writeCustody(bytes memory dst, uint i, uint host, bytes32 asset, uint amount) internal pure {
        uint spec = Specs.Custody;
        assembly ("memory-safe") {
            let p := add(add(dst, 0x20), i)
            mstore(p, spec)
            mstore(add(p, 0x08), host)
            mstore(add(p, 0x28), asset)
            mstore(add(p, 0x48), amount)
        }
    }

    /// @notice Write an ACCOUNT_AMOUNT block at `i`.
    /// @dev DANGER: Unchecked memory write. Reserve `Sizes.B96` bytes first.
    /// @param dst Destination buffer.
    /// @param i Relative write position.
    /// @param account Account identifier to encode.
    /// @param asset Asset identifier to encode.
    /// @param amount Account amount to encode.
    function writeAccountAmount(bytes memory dst, uint i, bytes32 account, bytes32 asset, uint amount) internal pure {
        uint spec = Specs.AccountAmount;
        assembly ("memory-safe") {
            let p := add(add(dst, 0x20), i)
            mstore(p, spec)
            mstore(add(p, 0x08), account)
            mstore(add(p, 0x28), asset)
            mstore(add(p, 0x48), amount)
        }
    }

    /// @notice Write a HOST_AMOUNT block at `i`.
    /// @dev DANGER: Unchecked memory write. Reserve `Sizes.B96` bytes first.
    /// @param dst Destination buffer.
    /// @param i Relative write position.
    /// @param host Host identifier to encode.
    /// @param asset Asset identifier to encode.
    /// @param amount Host amount to encode.
    function writeHostAmount(bytes memory dst, uint i, uint host, bytes32 asset, uint amount) internal pure {
        uint spec = Specs.HostAmount;
        assembly ("memory-safe") {
            let p := add(add(dst, 0x20), i)
            mstore(p, spec)
            mstore(add(p, 0x08), host)
            mstore(add(p, 0x28), asset)
            mstore(add(p, 0x48), amount)
        }
    }

    /// @notice Write a HOST_ACCOUNT_ASSET block at `i`.
    /// @dev DANGER: Unchecked memory write. Reserve `Sizes.B96` bytes first.
    /// @param dst Destination buffer.
    /// @param i Relative write position.
    /// @param host Host identifier to encode.
    /// @param account Account identifier to encode.
    /// @param asset Asset identifier to encode.
    function writeHostAccountAsset(bytes memory dst, uint i, uint host, bytes32 account, bytes32 asset) internal pure {
        uint spec = Specs.HostAccountAsset;
        assembly ("memory-safe") {
            let p := add(add(dst, 0x20), i)
            mstore(p, spec)
            mstore(add(p, 0x08), host)
            mstore(add(p, 0x28), account)
            mstore(add(p, 0x48), asset)
        }
    }

    /// @notice Write a LIMITS block with minimum amount and maximum debt.
    /// @dev Unchecked memory write; reserve Sizes.Limits bytes first.
    /// @param dst Destination buffer.
    /// @param i Relative write position.
    /// @param limits Packed minimum asset amount (high 128 bits) and maximum debt (low 128 bits).
    function writeLimits(bytes memory dst, uint i, uint limits) internal pure {
        uint spec = Specs.Limits;
        assembly ("memory-safe") {
            let p := add(add(dst, 0x20), i)
            mstore(p, spec)
            mstore(add(p, 0x08), limits)
        }
    }

    /// @notice Write a QUOTE with minimum amount and maximum debt.
    /// @dev Unchecked memory write; reserve Sizes.Quote bytes first.
    function writeQuote(
        bytes memory dst,
        uint i,
        bytes32 asset,
        bytes32 liability,
        bytes32 counterparty,
        uint limits
    ) internal pure {
        uint spec = Specs.Quote;
        assembly ("memory-safe") {
            let p := add(add(dst, 0x20), i)
            mstore(p, spec)
            mstore(add(p, 0x08), asset)
            mstore(add(p, 0x28), liability)
            mstore(add(p, 0x48), counterparty)
            mstore(add(p, 0x68), limits)
        }
    }

    // Position payload

    /// @notice Write a POSITION block at `i`.
    /// @dev DANGER: Unchecked memory write. Reserve `Sizes.Position` bytes first.
    /// @param dst Destination buffer.
    /// @param i Relative write position.
    /// @param asset Identifier for the asset side.
    /// @param amount Quantity on the asset side.
    /// @param liability Identifier for the liability side.
    /// @param debt Quantity owed on the liability side.
    /// @param counterparty Settlement counterparty: Rootzero (zero) or an account ID, including a host account.
    function writePosition(
        bytes memory dst,
        uint i,
        bytes32 asset,
        uint amount,
        bytes32 liability,
        uint debt,
        bytes32 counterparty
    ) internal pure {
        uint spec = Specs.Position;
        assembly ("memory-safe") {
            let p := add(add(dst, 0x20), i)
            mstore(p, spec)
            mstore(add(p, 0x08), asset)
            mstore(add(p, 0x28), amount)
            mstore(add(p, 0x48), liability)
            mstore(add(p, 0x68), debt)
            mstore(add(p, 0x88), counterparty)
        }
    }

    /// @notice Write a TRANSACTION block at `i`.
    /// @dev DANGER: Unchecked memory write. Reserve `Sizes.B128` bytes first.
    /// @param dst Destination buffer.
    /// @param i Relative write position.
    /// @param from Debit account identifier.
    /// @param to Credit account identifier.
    /// @param asset Asset identifier.
    /// @param amount Transaction amount.
    function writeTransaction(
        bytes memory dst,
        uint i,
        bytes32 from,
        bytes32 to,
        bytes32 asset,
        uint amount
    ) internal pure {
        uint spec = Specs.Transaction;
        assembly ("memory-safe") {
            let p := add(add(dst, 0x20), i)
            mstore(p, spec)
            mstore(add(p, 0x08), from)
            mstore(add(p, 0x28), to)
            mstore(add(p, 0x48), asset)
            mstore(add(p, 0x68), amount)
        }
    }

    /// @notice Write a HOST_ACCOUNT_AMOUNT block at `i`.
    /// @dev DANGER: Unchecked memory write. Reserve `Sizes.B128` bytes first.
    /// @param dst Destination buffer.
    /// @param i Relative write position.
    /// @param host Host identifier.
    /// @param account Account identifier.
    /// @param asset Asset identifier.
    /// @param amount Host account amount.
    function writeHostAccountAmount(
        bytes memory dst,
        uint i,
        uint host,
        bytes32 account,
        bytes32 asset,
        uint amount
    ) internal pure {
        uint spec = Specs.HostAccountAmount;
        assembly ("memory-safe") {
            let p := add(add(dst, 0x20), i)
            mstore(p, spec)
            mstore(add(p, 0x08), host)
            mstore(add(p, 0x28), account)
            mstore(add(p, 0x48), asset)
            mstore(add(p, 0x68), amount)
        }
    }

    // Dynamic payloads

    /// @notice Write a LIST block at `i`.
    /// @dev DANGER: Unchecked memory write. The caller must reserve the complete
    /// block size and ensure the payload length fits in uint32.
    /// @param dst Destination buffer.
    /// @param i Relative write position.
    /// @param value Encoded list payload.
    function writeList(bytes memory dst, uint i, bytes memory value) internal pure {
        uint len = value.length;
        uint key = uint32(Keys.List);
        assembly ("memory-safe") {
            let p := add(add(dst, 0x20), i)
            mstore(p, or(shl(224, key), shl(192, len)))
            mcopy(add(p, 0x08), add(value, 0x20), len)
        }
    }

    /// @notice Write a BYTES block at `i`.
    /// @dev DANGER: Unchecked memory write. The caller must reserve the complete
    /// block size and ensure the payload length fits in uint32.
    /// @param dst Destination buffer.
    /// @param i Relative write position.
    /// @param value Byte payload.
    function writeBytes(bytes memory dst, uint i, bytes memory value) internal pure {
        uint len = value.length;
        uint key = uint32(Keys.Bytes);
        assembly ("memory-safe") {
            let p := add(add(dst, 0x20), i)
            mstore(p, or(shl(224, key), shl(192, len)))
            mcopy(add(p, 0x08), add(value, 0x20), len)
        }
    }

    /// @notice Write a STRING block at `i`.
    /// @dev DANGER: Unchecked memory write. The caller must reserve the complete
    /// block size and ensure the payload length fits in uint32.
    /// @param dst Destination buffer.
    /// @param i Relative write position.
    /// @param value String payload.
    function writeString(bytes memory dst, uint i, string memory value) internal pure {
        uint len = bytes(value).length;
        uint key = uint32(Keys.String);
        assembly ("memory-safe") {
            let p := add(add(dst, 0x20), i)
            mstore(p, or(shl(224, key), shl(192, len)))
            mcopy(add(p, 0x08), add(value, 0x20), len)
        }
    }

    /// @notice Write a STEP block at `i`.
    /// @dev DANGER: Unchecked memory write. The caller must reserve the complete
    /// block size and ensure the encoded payload length fits in uint32.
    /// @param dst Destination buffer.
    /// @param i Relative write position.
    /// @param cmd Command identifier.
    /// @param value Native value assigned to the step.
    /// @param input Command input.
    function writeStep(bytes memory dst, uint i, uint cmd, uint value, bytes memory input) internal pure {
        uint len = 64 + Sizes.Header + input.length;
        uint key = uint32(Keys.Step);
        uint byteskey = uint32(Keys.Bytes);
        assembly ("memory-safe") {
            let p := add(add(dst, 0x20), i)
            mstore(p, or(shl(224, key), shl(192, len)))
            mstore(add(p, 0x08), cmd)
            mstore(add(p, 0x28), value)

            let q := add(p, 0x48)
            let inputlen := mload(input)
            mstore(q, or(shl(224, byteskey), shl(192, inputlen)))
            mcopy(add(q, 0x08), add(input, 0x20), inputlen)
        }
    }

    /// @notice Write a CALL block at `i`.
    /// @dev DANGER: Unchecked memory write. The caller must reserve the complete
    /// block size and ensure the encoded payload length fits in uint32.
    /// @param dst Destination buffer.
    /// @param i Relative write position.
    /// @param target Call target.
    /// @param resources Packed resources.
    /// @param payload Call payload.
    function writeCall(bytes memory dst, uint i, uint target, uint resources, bytes memory payload) internal pure {
        uint len = 64 + Sizes.Header + payload.length;
        uint key = uint32(Keys.Call);
        uint byteskey = uint32(Keys.Bytes);
        assembly ("memory-safe") {
            let p := add(add(dst, 0x20), i)
            mstore(p, or(shl(224, key), shl(192, len)))
            mstore(add(p, 0x08), target)
            mstore(add(p, 0x28), resources)

            let q := add(p, 0x48)
            let payloadlen := mload(payload)
            mstore(q, or(shl(224, byteskey), shl(192, payloadlen)))
            mcopy(add(q, 0x08), add(payload, 0x20), payloadlen)
        }
    }

    /// @notice Write a RELAY block at `i`.
    /// @dev DANGER: Unchecked memory write. The caller must reserve the complete
    /// block size and ensure the encoded payload length fits in uint32.
    /// @param dst Destination buffer.
    /// @param i Relative write position.
    /// @param input Command-specific handoff input.
    /// @param steps Remaining pipeline steps.
    function writeRelay(bytes memory dst, uint i, bytes memory input, bytes memory steps) internal pure {
        uint len = 2 * Sizes.Header + input.length + steps.length;
        uint key = uint32(Keys.Relay);
        uint byteskey = uint32(Keys.Bytes);
        assembly ("memory-safe") {
            let p := add(add(dst, 0x20), i)
            mstore(p, or(shl(224, key), shl(192, len)))
            let q := add(p, 0x08)
            let inputlen := mload(input)
            mstore(q, or(shl(224, byteskey), shl(192, inputlen)))
            mcopy(add(q, 0x08), add(input, 0x20), inputlen)
            q := add(add(q, 0x08), inputlen)
            let stepslen := mload(steps)
            mstore(q, or(shl(224, byteskey), shl(192, stepslen)))
            mcopy(add(q, 0x08), add(steps, 0x20), stepslen)
        }
    }

    /// @notice Write a DISPATCH block at `i`.
    /// @dev DANGER: Unchecked memory write. The caller must reserve the complete
    /// block size and ensure the encoded payload length fits in uint32.
    /// @param dst Destination buffer.
    /// @param i Relative write position.
    /// @param portal Destination portal.
    /// @param resources Packed resources.
    /// @param payload Dispatch payload.
    function writeDispatch(bytes memory dst, uint i, uint portal, uint resources, bytes memory payload) internal pure {
        uint len = 64 + Sizes.Header + payload.length;
        uint key = uint32(Keys.Dispatch);
        uint byteskey = uint32(Keys.Bytes);
        assembly ("memory-safe") {
            let p := add(add(dst, 0x20), i)
            mstore(p, or(shl(224, key), shl(192, len)))
            mstore(add(p, 0x08), portal)
            mstore(add(p, 0x28), resources)

            let q := add(p, 0x48)
            let payloadlen := mload(payload)
            mstore(q, or(shl(224, byteskey), shl(192, payloadlen)))
            mcopy(add(q, 0x08), add(payload, 0x20), payloadlen)
        }
    }

    /// @notice Write a CONTEXT block at `i`.
    /// @dev DANGER: Unchecked memory write. The caller must reserve the complete
    /// block size and ensure the encoded payload length fits in uint32.
    /// @param dst Destination buffer.
    /// @param i Relative write position.
    /// @param account Account identifier.
    /// @param state State payload.
    /// @param input Input payload.
    function writeContext(
        bytes memory dst,
        uint i,
        bytes32 account,
        bytes memory state,
        bytes memory input
    ) internal pure {
        uint len = 32 + 2 * Sizes.Header + state.length + input.length;
        uint key = uint32(Keys.Context);
        uint byteskey = uint32(Keys.Bytes);
        assembly ("memory-safe") {
            let p := add(add(dst, 0x20), i)
            mstore(p, or(shl(224, key), shl(192, len)))
            mstore(add(p, 0x08), account)

            let q := add(p, 0x28)
            let statelen := mload(state)
            mstore(q, or(shl(224, byteskey), shl(192, statelen)))
            mcopy(add(q, 0x08), add(state, 0x20), statelen)

            let r := add(add(q, 0x08), statelen)
            let inputlen := mload(input)
            mstore(r, or(shl(224, byteskey), shl(192, inputlen)))
            mcopy(add(r, 0x08), add(input, 0x20), inputlen)
        }
    }

    /// @notice Write a RECOVER block at `i`.
    /// @dev DANGER: Unchecked memory write. The caller must reserve the complete
    /// block size and ensure the encoded payload length fits in uint32.
    /// @param dst Destination buffer.
    /// @param i Relative write position.
    /// @param handler Recovery handler.
    /// @param resources Packed resources.
    /// @param recoverykey Recovery key.
    /// @param witness Recovery witness.
    function writeRecover(
        bytes memory dst,
        uint i,
        uint handler,
        uint resources,
        bytes32 recoverykey,
        bytes memory witness
    ) internal pure {
        uint len = 96 + Sizes.Header + witness.length;
        uint key = uint32(Keys.Recover);
        uint byteskey = uint32(Keys.Bytes);
        assembly ("memory-safe") {
            let p := add(add(dst, 0x20), i)
            mstore(p, or(shl(224, key), shl(192, len)))
            mstore(add(p, 0x08), handler)
            mstore(add(p, 0x28), resources)
            mstore(add(p, 0x48), recoverykey)

            let q := add(p, 0x68)
            let witnesslen := mload(witness)
            mstore(q, or(shl(224, byteskey), shl(192, witnesslen)))
            mcopy(add(q, 0x08), add(witness, 0x20), witnesslen)
        }
    }

    /// @notice Write a LABEL block at `i`.
    /// @dev DANGER: Unchecked memory write. The caller must reserve the complete
    /// block size and ensure the encoded payload length fits in uint32.
    /// @param dst Destination buffer.
    /// @param i Relative write position.
    /// @param namespace Label namespace.
    /// @param name Label text.
    function writeLabel(bytes memory dst, uint i, bytes32 namespace, string memory name) internal pure {
        uint len = 32 + Sizes.Header + bytes(name).length;
        uint key = uint32(Keys.Label);
        uint stringkey = uint32(Keys.String);
        assembly ("memory-safe") {
            let p := add(add(dst, 0x20), i)
            mstore(p, or(shl(224, key), shl(192, len)))
            mstore(add(p, 0x08), namespace)

            let q := add(p, 0x28)
            let namelen := mload(name)
            mstore(q, or(shl(224, stringkey), shl(192, namelen)))
            mcopy(add(q, 0x08), add(name, 0x20), namelen)
        }
    }

    /// @notice Write a SCHEMA block at `i`.
    /// @dev DANGER: Unchecked memory write. The caller must reserve the complete
    /// block size and ensure the encoded payload length fits in uint32.
    /// @param dst Destination buffer.
    /// @param i Relative write position.
    /// @param spec Block specification.
    /// @param body Schema body.
    /// @param name Schema name.
    function writeSchema(bytes memory dst, uint i, uint spec, string memory body, bytes32 name) internal pure {
        uint len = 64 + Sizes.Header + bytes(body).length;
        uint key = uint32(Keys.Schema);
        uint stringkey = uint32(Keys.String);
        assembly ("memory-safe") {
            let p := add(add(dst, 0x20), i)
            mstore(p, or(shl(224, key), shl(192, len)))
            mstore(add(p, 0x08), spec)

            let q := add(p, 0x28)
            let bodylen := mload(body)
            mstore(q, or(shl(224, stringkey), shl(192, bodylen)))
            mcopy(add(q, 0x08), add(body, 0x20), bodylen)
            mstore(add(add(q, 0x08), bodylen), name)
        }
    }

    // Calldata copy writers

    /// @notice Encode a custom block at `i`, copying its payload from calldata.
    /// @dev DANGER: Unchecked memory write. The caller must validate the payload
    /// length and reserve `Sizes.Header + payload.length` bytes first.
    function copy(bytes memory dst, uint i, bytes4 key, bytes calldata payload) internal pure {
        uint len = max32(payload.length);
        uint word = (uint(uint32(key)) << 224) | (len << 192);
        assembly ("memory-safe") {
            let p := add(add(dst, 0x20), i)
            mstore(p, word)
            calldatacopy(add(p, 0x08), payload.offset, len)
        }
    }

    /// @dev DANGER: len must equal payload.length and fit uint32. The caller must
    /// reserve the full header/payload and trailing header scratch space.
    /// Standalone copy retains its direct implementation and length validation.
    function copySized(bytes memory dst, uint i, bytes4 key, bytes calldata payload, uint len) internal pure {
        uint word = (uint(uint32(key)) << 224) | (len << 192);
        assembly ("memory-safe") {
            let p := add(add(dst, 0x20), i)
            mstore(p, word)
            calldatacopy(add(p, 0x08), payload.offset, len)
        }
    }

    /// @notice Encode a LIST block at `i`, copying its payload from calldata.
    function copyList(bytes memory dst, uint i, bytes calldata value) internal pure {
        copy(dst, i, Keys.List, value);
    }

    /// @notice Encode a BYTES block at `i`, copying its payload from calldata.
    function copyBytes(bytes memory dst, uint i, bytes calldata value) internal pure {
        copy(dst, i, Keys.Bytes, value);
    }

    /// @notice Encode a STRING block at `i`, copying its payload from calldata.
    function copyString(bytes memory dst, uint i, string calldata value) internal pure {
        copy(dst, i, Keys.String, bytes(value));
    }

    /// @dev Encode a two-word composite with a nested BYTES block copied from calldata.
    function copyComposite(
        bytes memory dst,
        uint i,
        bytes4 blockkey,
        uint a,
        uint b,
        bytes calldata value
    ) private pure {
        uint len = max32(64 + Sizes.Header + value.length);
        uint key = uint32(blockkey);
        uint byteskey = uint32(Keys.Bytes);
        assembly ("memory-safe") {
            let p := add(add(dst, 0x20), i)
            mstore(p, or(shl(224, key), shl(192, len)))
            mstore(add(p, 0x08), a)
            mstore(add(p, 0x28), b)

            let q := add(p, 0x48)
            let valuelen := value.length
            mstore(q, or(shl(224, byteskey), shl(192, valuelen)))
            calldatacopy(add(q, 0x08), value.offset, valuelen)
        }
    }

    /// @notice Encode a STEP block at `i`, copying its nested input from calldata.
    function copyStep(bytes memory dst, uint i, uint cmd, uint value, bytes calldata input) internal pure {
        uint len = max32(64 + Sizes.Header + input.length);
        uint key = uint32(Keys.Step);
        uint byteskey = uint32(Keys.Bytes);
        assembly ("memory-safe") {
            let p := add(add(dst, 0x20), i)
            mstore(p, or(shl(224, key), shl(192, len)))
            mstore(add(p, 0x08), cmd)
            mstore(add(p, 0x28), value)

            let q := add(p, 0x48)
            let inputlen := input.length
            mstore(q, or(shl(224, byteskey), shl(192, inputlen)))
            calldatacopy(add(q, 0x08), input.offset, inputlen)
        }
    }

    /// @notice Encode a CALL block at `i`, copying its nested payload from calldata.
    function copyCall(bytes memory dst, uint i, uint target, uint resources, bytes calldata payload) internal pure {
        copyComposite(dst, i, Keys.Call, target, resources, payload);
    }

    /// @notice Encode a RELAY block at `i`, copying its nested streams from calldata.
    function copyRelay(bytes memory dst, uint i, bytes calldata input, bytes calldata steps) internal pure {
        uint len = 2 * Sizes.Header + input.length + steps.length;
        uint key = uint32(Keys.Relay);
        uint byteskey = uint32(Keys.Bytes);
        assembly ("memory-safe") {
            let p := add(add(dst, 0x20), i)
            mstore(p, or(shl(224, key), shl(192, len)))
            let q := add(p, 0x08)
            let inputlen := input.length
            mstore(q, or(shl(224, byteskey), shl(192, inputlen)))
            calldatacopy(add(q, 0x08), input.offset, inputlen)
            q := add(add(q, 0x08), inputlen)
            let stepslen := steps.length
            mstore(q, or(shl(224, byteskey), shl(192, stepslen)))
            calldatacopy(add(q, 0x08), steps.offset, stepslen)
        }
    }

    /// @notice Encode a DISPATCH block at `i`, copying its nested payload from calldata.
    function copyDispatch(bytes memory dst, uint i, uint portal, uint resources, bytes calldata payload) internal pure {
        copyComposite(dst, i, Keys.Dispatch, portal, resources, payload);
    }

    /// @notice Encode a CONTEXT block at `i`, copying its nested streams from calldata.
    function copyContext(
        bytes memory dst,
        uint i,
        bytes32 account,
        bytes calldata state,
        bytes calldata input
    ) internal pure {
        uint len = max32(32 + 2 * Sizes.Header + state.length + input.length);
        uint key = uint32(Keys.Context);
        uint byteskey = uint32(Keys.Bytes);
        assembly ("memory-safe") {
            let p := add(add(dst, 0x20), i)
            mstore(p, or(shl(224, key), shl(192, len)))
            mstore(add(p, 0x08), account)

            let q := add(p, 0x28)
            let statelen := state.length
            mstore(q, or(shl(224, byteskey), shl(192, statelen)))
            calldatacopy(add(q, 0x08), state.offset, statelen)

            let r := add(add(q, 0x08), statelen)
            let inputlen := input.length
            mstore(r, or(shl(224, byteskey), shl(192, inputlen)))
            calldatacopy(add(r, 0x08), input.offset, inputlen)
        }
    }

    /// @notice Encode a RECOVER block at `i`, copying its nested witness from calldata.
    function copyRecover(
        bytes memory dst,
        uint i,
        uint handler,
        uint resources,
        bytes32 recoverykey,
        bytes calldata witness
    ) internal pure {
        uint len = max32(96 + Sizes.Header + witness.length);
        uint key = uint32(Keys.Recover);
        uint byteskey = uint32(Keys.Bytes);
        assembly ("memory-safe") {
            let p := add(add(dst, 0x20), i)
            mstore(p, or(shl(224, key), shl(192, len)))
            mstore(add(p, 0x08), handler)
            mstore(add(p, 0x28), resources)
            mstore(add(p, 0x48), recoverykey)

            let q := add(p, 0x68)
            let witnesslen := witness.length
            mstore(q, or(shl(224, byteskey), shl(192, witnesslen)))
            calldatacopy(add(q, 0x08), witness.offset, witnesslen)
        }
    }

    /// @dev Factory-only writers. The destination's complete length has already
    /// passed max32 and allocation; reuse it for the outer payload header.
    function writeCompositeAllocated(
        bytes memory dst,
        bytes4 blockkey,
        uint cmd,
        uint value,
        bytes memory input
    ) private pure {
        uint key = uint32(blockkey);
        uint byteskey = uint32(Keys.Bytes);
        assembly ("memory-safe") {
            let p := add(dst, 0x20)
            mstore(p, or(shl(224, key), shl(192, sub(mload(dst), 8))))
            mstore(add(p, 0x08), cmd)
            mstore(add(p, 0x28), value)

            let q := add(p, 0x48)
            let inputlen := mload(input)
            mstore(q, or(shl(224, byteskey), shl(192, inputlen)))
            mcopy(add(q, 0x08), add(input, 0x20), inputlen)
        }
    }

    function writeRelayAllocated(bytes memory dst, bytes memory input, bytes memory steps) private pure {
        uint key = uint32(Keys.Relay);
        uint byteskey = uint32(Keys.Bytes);
        assembly ("memory-safe") {
            let p := add(dst, 0x20)
            mstore(p, or(shl(224, key), shl(192, sub(mload(dst), 8))))
            let q := add(p, 0x08)
            let inputlen := mload(input)
            mstore(q, or(shl(224, byteskey), shl(192, inputlen)))
            mcopy(add(q, 0x08), add(input, 0x20), inputlen)
            q := add(add(q, 0x08), inputlen)
            let stepslen := mload(steps)
            mstore(q, or(shl(224, byteskey), shl(192, stepslen)))
            mcopy(add(q, 0x08), add(steps, 0x20), stepslen)
        }
    }

    function writeContextAllocated(
        bytes memory dst,
        bytes32 account,
        bytes memory state,
        bytes memory input
    ) private pure {
        uint key = uint32(Keys.Context);
        uint byteskey = uint32(Keys.Bytes);
        assembly ("memory-safe") {
            let p := add(dst, 0x20)
            mstore(p, or(shl(224, key), shl(192, sub(mload(dst), 8))))
            mstore(add(p, 0x08), account)

            let q := add(p, 0x28)
            let statelen := mload(state)
            mstore(q, or(shl(224, byteskey), shl(192, statelen)))
            mcopy(add(q, 0x08), add(state, 0x20), statelen)

            let r := add(add(q, 0x08), statelen)
            let inputlen := mload(input)
            mstore(r, or(shl(224, byteskey), shl(192, inputlen)))
            mcopy(add(r, 0x08), add(input, 0x20), inputlen)
        }
    }

    function writeRecoverAllocated(
        bytes memory dst,
        uint handler,
        uint resources,
        bytes32 recoverykey,
        bytes memory witness
    ) private pure {
        uint key = uint32(Keys.Recover);
        uint byteskey = uint32(Keys.Bytes);
        assembly ("memory-safe") {
            let p := add(dst, 0x20)
            mstore(p, or(shl(224, key), shl(192, sub(mload(dst), 8))))
            mstore(add(p, 0x08), handler)
            mstore(add(p, 0x28), resources)
            mstore(add(p, 0x48), recoverykey)

            let q := add(p, 0x68)
            let witnesslen := mload(witness)
            mstore(q, or(shl(224, byteskey), shl(192, witnesslen)))
            mcopy(add(q, 0x08), add(witness, 0x20), witnesslen)
        }
    }

    function copyCompositeAllocated(
        bytes memory dst,
        bytes4 blockkey,
        uint cmd,
        uint value,
        bytes calldata input
    ) private pure {
        uint key = uint32(blockkey);
        uint byteskey = uint32(Keys.Bytes);
        assembly ("memory-safe") {
            let p := add(dst, 0x20)
            mstore(p, or(shl(224, key), shl(192, sub(mload(dst), 8))))
            mstore(add(p, 0x08), cmd)
            mstore(add(p, 0x28), value)

            let q := add(p, 0x48)
            let inputlen := input.length
            mstore(q, or(shl(224, byteskey), shl(192, inputlen)))
            calldatacopy(add(q, 0x08), input.offset, inputlen)
        }
    }

    function copyRelayAllocated(bytes memory dst, bytes calldata input, bytes calldata steps) private pure {
        uint key = uint32(Keys.Relay);
        uint byteskey = uint32(Keys.Bytes);
        assembly ("memory-safe") {
            let p := add(dst, 0x20)
            mstore(p, or(shl(224, key), shl(192, sub(mload(dst), 8))))
            let q := add(p, 0x08)
            let inputlen := input.length
            mstore(q, or(shl(224, byteskey), shl(192, inputlen)))
            calldatacopy(add(q, 0x08), input.offset, inputlen)
            q := add(add(q, 0x08), inputlen)
            let stepslen := steps.length
            mstore(q, or(shl(224, byteskey), shl(192, stepslen)))
            calldatacopy(add(q, 0x08), steps.offset, stepslen)
        }
    }

    function copyContextAllocated(
        bytes memory dst,
        bytes32 account,
        bytes calldata state,
        bytes calldata input
    ) private pure {
        uint key = uint32(Keys.Context);
        uint byteskey = uint32(Keys.Bytes);
        assembly ("memory-safe") {
            let p := add(dst, 0x20)
            mstore(p, or(shl(224, key), shl(192, sub(mload(dst), 8))))
            mstore(add(p, 0x08), account)

            let q := add(p, 0x28)
            let statelen := state.length
            mstore(q, or(shl(224, byteskey), shl(192, statelen)))
            calldatacopy(add(q, 0x08), state.offset, statelen)

            let r := add(add(q, 0x08), statelen)
            let inputlen := input.length
            mstore(r, or(shl(224, byteskey), shl(192, inputlen)))
            calldatacopy(add(r, 0x08), input.offset, inputlen)
        }
    }

    function copyRecoverAllocated(
        bytes memory dst,
        uint handler,
        uint resources,
        bytes32 recoverykey,
        bytes calldata witness
    ) private pure {
        uint key = uint32(Keys.Recover);
        uint byteskey = uint32(Keys.Bytes);
        assembly ("memory-safe") {
            let p := add(dst, 0x20)
            mstore(p, or(shl(224, key), shl(192, sub(mload(dst), 8))))
            mstore(add(p, 0x08), handler)
            mstore(add(p, 0x28), resources)
            mstore(add(p, 0x48), recoverykey)

            let q := add(p, 0x68)
            let witnesslen := witness.length
            mstore(q, or(shl(224, byteskey), shl(192, witnesslen)))
            calldatacopy(add(q, 0x08), witness.offset, witnesslen)
        }
    }

    function writeLabelAllocated(bytes memory dst, bytes32 namespace, string memory name) private pure {
        uint key = uint32(Keys.Label);
        uint stringkey = uint32(Keys.String);
        assembly ("memory-safe") {
            let p := add(dst, 0x20)
            mstore(p, or(shl(224, key), shl(192, sub(mload(dst), 8))))
            mstore(add(p, 0x08), namespace)

            let q := add(p, 0x28)
            let namelen := mload(name)
            mstore(q, or(shl(224, stringkey), shl(192, namelen)))
            mcopy(add(q, 0x08), add(name, 0x20), namelen)
        }
    }

    function writeSchemaAllocated(bytes memory dst, uint spec, string memory body, bytes32 name) private pure {
        uint key = uint32(Keys.Schema);
        uint stringkey = uint32(Keys.String);
        assembly ("memory-safe") {
            let p := add(dst, 0x20)
            mstore(p, or(shl(224, key), shl(192, sub(mload(dst), 8))))
            mstore(add(p, 0x08), spec)

            let q := add(p, 0x28)
            let bodylen := mload(body)
            mstore(q, or(shl(224, stringkey), shl(192, bodylen)))
            mcopy(add(q, 0x08), add(body, 0x20), bodylen)
            mstore(add(add(q, 0x08), bodylen), name)
        }
    }

    /// @dev DANGER: Caller must reserve size bytes plus header scratch space,
    /// prove size fits uint32, and pass the exact complete block size.
    function writeCompositeSized(
        bytes memory dst,
        uint i,
        bytes4 blockkey,
        uint cmd,
        uint value,
        bytes memory input,
        uint size
    ) internal pure {
        uint key = uint32(blockkey);
        uint byteskey = uint32(Keys.Bytes);
        assembly ("memory-safe") {
            let p := add(add(dst, 0x20), i)
            mstore(p, or(shl(224, key), shl(192, sub(size, 8))))
            mstore(add(p, 0x08), cmd)
            mstore(add(p, 0x28), value)

            let q := add(p, 0x48)
            let inputlen := mload(input)
            mstore(q, or(shl(224, byteskey), shl(192, inputlen)))
            mcopy(add(q, 0x08), add(input, 0x20), inputlen)
        }
    }

    /// @dev DANGER: Caller must reserve size bytes plus header scratch space,
    /// prove size fits uint32, and pass the exact complete block size.
    function writeRelaySized(
        bytes memory dst,
        uint i,
        bytes memory input,
        bytes memory steps,
        uint size
    ) internal pure {
        uint key = uint32(Keys.Relay);
        uint byteskey = uint32(Keys.Bytes);
        assembly ("memory-safe") {
            let p := add(add(dst, 0x20), i)
            mstore(p, or(shl(224, key), shl(192, sub(size, 8))))
            let q := add(p, 0x08)
            let inputlen := mload(input)
            mstore(q, or(shl(224, byteskey), shl(192, inputlen)))
            mcopy(add(q, 0x08), add(input, 0x20), inputlen)
            q := add(add(q, 0x08), inputlen)
            let stepslen := mload(steps)
            mstore(q, or(shl(224, byteskey), shl(192, stepslen)))
            mcopy(add(q, 0x08), add(steps, 0x20), stepslen)
        }
    }

    /// @dev DANGER: Caller must reserve size bytes plus header scratch space,
    /// prove size fits uint32, and pass the exact complete block size.
    function writeContextSized(
        bytes memory dst,
        uint i,
        bytes32 account,
        bytes memory state,
        bytes memory input,
        uint size
    ) internal pure {
        uint key = uint32(Keys.Context);
        uint byteskey = uint32(Keys.Bytes);
        assembly ("memory-safe") {
            let p := add(add(dst, 0x20), i)
            mstore(p, or(shl(224, key), shl(192, sub(size, 8))))
            mstore(add(p, 0x08), account)

            let q := add(p, 0x28)
            let statelen := mload(state)
            mstore(q, or(shl(224, byteskey), shl(192, statelen)))
            mcopy(add(q, 0x08), add(state, 0x20), statelen)

            let r := add(add(q, 0x08), statelen)
            let inputlen := mload(input)
            mstore(r, or(shl(224, byteskey), shl(192, inputlen)))
            mcopy(add(r, 0x08), add(input, 0x20), inputlen)
        }
    }

    /// @dev DANGER: Caller must reserve size bytes plus header scratch space,
    /// prove size fits uint32, and pass the exact complete block size.
    function writeRecoverSized(
        bytes memory dst,
        uint i,
        uint handler,
        uint resources,
        bytes32 recoverykey,
        bytes memory witness,
        uint size
    ) internal pure {
        uint key = uint32(Keys.Recover);
        uint byteskey = uint32(Keys.Bytes);
        assembly ("memory-safe") {
            let p := add(add(dst, 0x20), i)
            mstore(p, or(shl(224, key), shl(192, sub(size, 8))))
            mstore(add(p, 0x08), handler)
            mstore(add(p, 0x28), resources)
            mstore(add(p, 0x48), recoverykey)

            let q := add(p, 0x68)
            let witnesslen := mload(witness)
            mstore(q, or(shl(224, byteskey), shl(192, witnesslen)))
            mcopy(add(q, 0x08), add(witness, 0x20), witnesslen)
        }
    }

    /// @dev DANGER: Caller must reserve size bytes plus header scratch space,
    /// prove size fits uint32, and pass the exact complete block size.
    function writeLabelSized(bytes memory dst, uint i, bytes32 namespace, string memory name, uint size) internal pure {
        uint key = uint32(Keys.Label);
        uint stringkey = uint32(Keys.String);
        assembly ("memory-safe") {
            let p := add(add(dst, 0x20), i)
            mstore(p, or(shl(224, key), shl(192, sub(size, 8))))
            mstore(add(p, 0x08), namespace)

            let q := add(p, 0x28)
            let namelen := mload(name)
            mstore(q, or(shl(224, stringkey), shl(192, namelen)))
            mcopy(add(q, 0x08), add(name, 0x20), namelen)
        }
    }

    /// @dev DANGER: Caller must reserve size bytes plus header scratch space,
    /// prove size fits uint32, and pass the exact complete block size.
    function writeSchemaSized(
        bytes memory dst,
        uint i,
        uint spec,
        string memory body,
        bytes32 name,
        uint size
    ) internal pure {
        uint key = uint32(Keys.Schema);
        uint stringkey = uint32(Keys.String);
        assembly ("memory-safe") {
            let p := add(add(dst, 0x20), i)
            mstore(p, or(shl(224, key), shl(192, sub(size, 8))))
            mstore(add(p, 0x08), spec)

            let q := add(p, 0x28)
            let bodylen := mload(body)
            mstore(q, or(shl(224, stringkey), shl(192, bodylen)))
            mcopy(add(q, 0x08), add(body, 0x20), bodylen)
            mstore(add(add(q, 0x08), bodylen), name)
        }
    }

    /// @dev DANGER: Caller must reserve size bytes plus header scratch space,
    /// prove size fits uint32, and pass the exact complete block size.
    function copyCompositeSized(
        bytes memory dst,
        uint i,
        bytes4 blockkey,
        uint cmd,
        uint value,
        bytes calldata input,
        uint size
    ) internal pure {
        uint key = uint32(blockkey);
        uint byteskey = uint32(Keys.Bytes);
        assembly ("memory-safe") {
            let p := add(add(dst, 0x20), i)
            mstore(p, or(shl(224, key), shl(192, sub(size, 8))))
            mstore(add(p, 0x08), cmd)
            mstore(add(p, 0x28), value)

            let q := add(p, 0x48)
            let inputlen := input.length
            mstore(q, or(shl(224, byteskey), shl(192, inputlen)))
            calldatacopy(add(q, 0x08), input.offset, inputlen)
        }
    }

    /// @dev DANGER: Caller must reserve size bytes plus header scratch space,
    /// prove size fits uint32, and pass the exact complete block size.
    function copyRelaySized(
        bytes memory dst,
        uint i,
        bytes calldata input,
        bytes calldata steps,
        uint size
    ) internal pure {
        uint key = uint32(Keys.Relay);
        uint byteskey = uint32(Keys.Bytes);
        assembly ("memory-safe") {
            let p := add(add(dst, 0x20), i)
            mstore(p, or(shl(224, key), shl(192, sub(size, 8))))
            let q := add(p, 0x08)
            let inputlen := input.length
            mstore(q, or(shl(224, byteskey), shl(192, inputlen)))
            calldatacopy(add(q, 0x08), input.offset, inputlen)
            q := add(add(q, 0x08), inputlen)
            let stepslen := steps.length
            mstore(q, or(shl(224, byteskey), shl(192, stepslen)))
            calldatacopy(add(q, 0x08), steps.offset, stepslen)
        }
    }

    /// @dev DANGER: Caller must reserve size bytes plus header scratch space,
    /// prove size fits uint32, and pass the exact complete block size.
    function copyContextSized(
        bytes memory dst,
        uint i,
        bytes32 account,
        bytes calldata state,
        bytes calldata input,
        uint size
    ) internal pure {
        uint key = uint32(Keys.Context);
        uint byteskey = uint32(Keys.Bytes);
        assembly ("memory-safe") {
            let p := add(add(dst, 0x20), i)
            mstore(p, or(shl(224, key), shl(192, sub(size, 8))))
            mstore(add(p, 0x08), account)

            let q := add(p, 0x28)
            let statelen := state.length
            mstore(q, or(shl(224, byteskey), shl(192, statelen)))
            calldatacopy(add(q, 0x08), state.offset, statelen)

            let r := add(add(q, 0x08), statelen)
            let inputlen := input.length
            mstore(r, or(shl(224, byteskey), shl(192, inputlen)))
            calldatacopy(add(r, 0x08), input.offset, inputlen)
        }
    }

    /// @dev DANGER: Caller must reserve size bytes plus header scratch space,
    /// prove size fits uint32, and pass the exact complete block size.
    function copyRecoverSized(
        bytes memory dst,
        uint i,
        uint handler,
        uint resources,
        bytes32 recoverykey,
        bytes calldata witness,
        uint size
    ) internal pure {
        uint key = uint32(Keys.Recover);
        uint byteskey = uint32(Keys.Bytes);
        assembly ("memory-safe") {
            let p := add(add(dst, 0x20), i)
            mstore(p, or(shl(224, key), shl(192, sub(size, 8))))
            mstore(add(p, 0x08), handler)
            mstore(add(p, 0x28), resources)
            mstore(add(p, 0x48), recoverykey)

            let q := add(p, 0x68)
            let witnesslen := witness.length
            mstore(q, or(shl(224, byteskey), shl(192, witnesslen)))
            calldatacopy(add(q, 0x08), witness.offset, witnesslen)
        }
    }

    // -------------------------------------------------------------------------
    // Calldata decoding
    // -------------------------------------------------------------------------

    // Raw reads

    /// @notice Read one byte from an absolute calldata position.
    /// @dev DANGER: Unchecked calldata read. Values beyond calldata are zero-padded.
    /// @param abs Absolute calldata position.
    /// @return value Decoded one-byte value.
    function read1(uint abs) internal pure returns (bytes1 value) {
        return bytes1(read32(abs));
    }

    /// @notice Read two bytes from an absolute calldata position.
    /// @dev DANGER: Unchecked calldata read. Values beyond calldata are zero-padded.
    /// @param abs Absolute calldata position.
    /// @return value Decoded two-byte value.
    function read2(uint abs) internal pure returns (bytes2 value) {
        return bytes2(read32(abs));
    }

    /// @notice Read four bytes from an absolute calldata position.
    /// @dev DANGER: Unchecked calldata read. Values beyond calldata are zero-padded.
    /// @param abs Absolute calldata position.
    /// @return value Decoded four-byte value.
    function read4(uint abs) internal pure returns (bytes4 value) {
        return bytes4(read32(abs));
    }

    /// @notice Read eight bytes from an absolute calldata position.
    /// @dev DANGER: Unchecked calldata read. Values beyond calldata are zero-padded.
    /// @param abs Absolute calldata position.
    /// @return value Decoded eight-byte value.
    function read8(uint abs) internal pure returns (bytes8 value) {
        return bytes8(read32(abs));
    }

    /// @notice Read sixteen bytes from an absolute calldata position.
    /// @dev DANGER: Unchecked calldata read. Values beyond calldata are zero-padded.
    /// @param abs Absolute calldata position.
    /// @return value Decoded sixteen-byte value.
    function read16(uint abs) internal pure returns (bytes16 value) {
        return bytes16(read32(abs));
    }

    /// @notice Read one word from an absolute calldata position.
    /// @dev DANGER: Unchecked calldata read. Values beyond calldata are zero-padded.
    /// @param abs Absolute calldata position.
    /// @return value Decoded word.
    function read32(uint abs) internal pure returns (bytes32 value) {
        assembly ("memory-safe") {
            value := calldataload(abs)
        }
    }

    // Comparison reads

    /// @notice Read one word and require it to equal the word at another absolute calldata position.
    /// @dev DANGER: Unchecked calldata reads. Values beyond calldata are zero-padded.
    ///      Reverts with UnexpectedValue() when the words differ.
    /// @param abs Absolute calldata position to read and return.
    /// @param otherAbs Absolute calldata position to compare against.
    /// @return value Matching word.
    function readEqualAt32(uint abs, uint otherAbs) internal pure returns (bytes32 value) {
        assembly ("memory-safe") {
            value := calldataload(abs)
            if iszero(eq(value, calldataload(otherAbs))) {
                mstore(0, shl(224, 0x123146a6)) // UnexpectedValue()
                revert(0, 4)
            }
        }
    }

    /// @notice Read two words and require the first to differ from the second.
    /// @dev DANGER: Unchecked calldata reads. Values beyond calldata are zero-padded.
    ///      Compares unsigned words and reverts with UnexpectedValue() if the comparison fails.
    /// @param abs Absolute calldata position to read and return.
    /// @param otherAbs Absolute calldata position to compare against.
    /// @return value Word at abs.
    /// @return other Word at otherAbs.
    function readNotEqualAt32(uint abs, uint otherAbs) internal pure returns (bytes32 value, bytes32 other) {
        assembly ("memory-safe") {
            value := calldataload(abs)
            other := calldataload(otherAbs)
            if eq(value, other) {
                mstore(0, shl(224, 0x123146a6)) // UnexpectedValue()
                revert(0, 4)
            }
        }
    }

    /// @notice Read two words and require the first to be less than the second.
    /// @dev DANGER: Unchecked calldata reads. Values beyond calldata are zero-padded.
    ///      Compares unsigned words and reverts with OutOfRange() if the comparison fails.
    /// @param abs Absolute calldata position to read and return.
    /// @param otherAbs Absolute calldata position to compare against.
    /// @return value Word at abs.
    /// @return other Word at otherAbs.
    function readLtAt32(uint abs, uint otherAbs) internal pure returns (bytes32 value, bytes32 other) {
        assembly ("memory-safe") {
            value := calldataload(abs)
            other := calldataload(otherAbs)
            if iszero(lt(value, other)) {
                mstore(0, shl(224, 0x7db3aba7)) // OutOfRange()
                revert(0, 4)
            }
        }
    }

    /// @notice Read two words and require the first to be less than or equal to the second.
    /// @dev DANGER: Unchecked calldata reads. Values beyond calldata are zero-padded.
    ///      Compares unsigned words and reverts with OutOfRange() if the comparison fails.
    /// @param abs Absolute calldata position to read and return.
    /// @param otherAbs Absolute calldata position to compare against.
    /// @return value Word at abs.
    /// @return other Word at otherAbs.
    function readLeAt32(uint abs, uint otherAbs) internal pure returns (bytes32 value, bytes32 other) {
        assembly ("memory-safe") {
            value := calldataload(abs)
            other := calldataload(otherAbs)
            if gt(value, other) {
                mstore(0, shl(224, 0x7db3aba7)) // OutOfRange()
                revert(0, 4)
            }
        }
    }

    /// @notice Read two words and require the first to be greater than the second.
    /// @dev DANGER: Unchecked calldata reads. Values beyond calldata are zero-padded.
    ///      Compares unsigned words and reverts with OutOfRange() if the comparison fails.
    /// @param abs Absolute calldata position to read and return.
    /// @param otherAbs Absolute calldata position to compare against.
    /// @return value Word at abs.
    /// @return other Word at otherAbs.
    function readGtAt32(uint abs, uint otherAbs) internal pure returns (bytes32 value, bytes32 other) {
        assembly ("memory-safe") {
            value := calldataload(abs)
            other := calldataload(otherAbs)
            if iszero(gt(value, other)) {
                mstore(0, shl(224, 0x7db3aba7)) // OutOfRange()
                revert(0, 4)
            }
        }
    }

    /// @notice Read two words and require the first to be greater than or equal to the second.
    /// @dev DANGER: Unchecked calldata reads. Values beyond calldata are zero-padded.
    ///      Compares unsigned words and reverts with OutOfRange() if the comparison fails.
    /// @param abs Absolute calldata position to read and return.
    /// @param otherAbs Absolute calldata position to compare against.
    /// @return value Word at abs.
    /// @return other Word at otherAbs.
    function readGeAt32(uint abs, uint otherAbs) internal pure returns (bytes32 value, bytes32 other) {
        assembly ("memory-safe") {
            value := calldataload(abs)
            other := calldataload(otherAbs)
            if lt(value, other) {
                mstore(0, shl(224, 0x7db3aba7)) // OutOfRange()
                revert(0, 4)
            }
        }
    }

    // Value requirements

    /// @notice Require the byte at an absolute calldata position to match `expected`.
    /// @dev DANGER: Unchecked calldata read. Values beyond calldata are zero-padded.
    /// @param abs Absolute calldata position.
    /// @param expected Expected byte.
    function require1(uint abs, bytes1 expected) internal pure {
        if (read1(abs) != expected) revert UnexpectedValue();
    }

    /// @notice Require the two bytes at an absolute calldata position to match `expected`.
    /// @dev DANGER: Unchecked calldata read. Values beyond calldata are zero-padded.
    /// @param abs Absolute calldata position.
    /// @param expected Expected two-byte value.
    function require2(uint abs, bytes2 expected) internal pure {
        if (read2(abs) != expected) revert UnexpectedValue();
    }

    /// @notice Require the four bytes at an absolute calldata position to match `expected`.
    /// @dev DANGER: Unchecked calldata read. Values beyond calldata are zero-padded.
    /// @param abs Absolute calldata position.
    /// @param expected Expected four-byte value.
    function require4(uint abs, bytes4 expected) internal pure {
        if (read4(abs) != expected) revert UnexpectedValue();
    }

    /// @notice Require the eight bytes at an absolute calldata position to match `expected`.
    /// @dev DANGER: Unchecked calldata read. Values beyond calldata are zero-padded.
    /// @param abs Absolute calldata position.
    /// @param expected Expected eight-byte value.
    function require8(uint abs, bytes8 expected) internal pure {
        if (read8(abs) != expected) revert UnexpectedValue();
    }

    /// @notice Require the sixteen bytes at an absolute calldata position to match `expected`.
    /// @dev DANGER: Unchecked calldata read. Values beyond calldata are zero-padded.
    /// @param abs Absolute calldata position.
    /// @param expected Expected sixteen-byte value.
    function require16(uint abs, bytes16 expected) internal pure {
        if (read16(abs) != expected) revert UnexpectedValue();
    }

    /// @notice Require the word at an absolute calldata position to match `expected`.
    /// @dev DANGER: Unchecked calldata read. Values beyond calldata are zero-padded.
    /// @param abs Absolute calldata position.
    /// @param expected Expected word.
    function require32(uint abs, bytes32 expected) internal pure {
        if (read32(abs) != expected) revert UnexpectedValue();
    }

    // Generic block unpackers

    /// @notice Validate a block against `spec` and return its payload.
    /// @param abs Absolute block position.
    /// @param spec Expected block specification.
    /// @return value Decoded payload.
    /// @return end Absolute position after the block.
    function unpackRaw(uint abs, uint spec) internal pure returns (bytes calldata value, uint end) {
        (abs, end) = enter(abs, spec);
        value = msg.data[abs:end];
    }

    /// @notice Decode a spec-validated one-word block at `abs`.
    /// @param abs Absolute block position.
    /// @param spec Expected block specification.
    /// @return a First payload word.
    /// @return end Absolute position after the block.
    function unpack32(uint abs, uint spec) internal pure returns (bytes32 a, uint end) {
        (abs, end) = expectFixed(abs, Specs.key(spec), 32);
        a = read32(abs);
    }

    /// @notice Decode a spec-validated two-word block at `abs`.
    /// @param abs Absolute block position.
    /// @param spec Expected block specification.
    /// @return a First payload word.
    /// @return b Second payload word.
    /// @return end Absolute position after the block.
    function unpack64(uint abs, uint spec) internal pure returns (bytes32 a, bytes32 b, uint end) {
        (abs, end) = expectFixed(abs, Specs.key(spec), 64);
        assembly ("memory-safe") {
            a := calldataload(abs)
            b := calldataload(add(abs, 0x20))
        }
    }

    /// @notice Decode a spec-validated three-word block at `abs`.
    /// @param abs Absolute block position.
    /// @param spec Expected block specification.
    /// @return a First payload word.
    /// @return b Second payload word.
    /// @return c Third payload word.
    /// @return end Absolute position after the block.
    function unpack96(uint abs, uint spec) internal pure returns (bytes32 a, bytes32 b, bytes32 c, uint end) {
        (abs, end) = expectFixed(abs, Specs.key(spec), 96);
        assembly ("memory-safe") {
            a := calldataload(abs)
            b := calldataload(add(abs, 0x20))
            c := calldataload(add(abs, 0x40))
        }
    }

    /// @notice Decode a spec-validated four-word block at `abs`.
    /// @param abs Absolute block position.
    /// @param spec Expected block specification.
    /// @return a First payload word.
    /// @return b Second payload word.
    /// @return c Third payload word.
    /// @return d Fourth payload word.
    /// @return end Absolute position after the block.
    function unpack128(
        uint abs,
        uint spec
    ) internal pure returns (bytes32 a, bytes32 b, bytes32 c, bytes32 d, uint end) {
        (abs, end) = expectFixed(abs, Specs.key(spec), 128);
        assembly ("memory-safe") {
            a := calldataload(abs)
            b := calldataload(add(abs, 0x20))
            c := calldataload(add(abs, 0x40))
            d := calldataload(add(abs, 0x60))
        }
    }

    /// @notice Decode a spec-validated five-word block at `abs`.
    /// @param abs Absolute block position.
    /// @param spec Expected block specification.
    /// @return a First payload word.
    /// @return b Second payload word.
    /// @return c Third payload word.
    /// @return d Fourth payload word.
    /// @return e Fifth payload word.
    /// @return end Absolute position after the block.
    function unpack160(
        uint abs,
        uint spec
    ) internal pure returns (bytes32 a, bytes32 b, bytes32 c, bytes32 d, bytes32 e, uint end) {
        (abs, end) = expectFixed(abs, Specs.key(spec), 160);
        assembly ("memory-safe") {
            a := calldataload(abs)
            b := calldataload(add(abs, 0x20))
            c := calldataload(add(abs, 0x40))
            d := calldataload(add(abs, 0x60))
            e := calldataload(add(abs, 0x80))
        }
    }

    /// @notice Decode a spec-validated asset and amount pair.
    /// @param abs Absolute block position.
    /// @param spec Expected block specification.
    /// @return asset Decoded asset identifier.
    /// @return amount Decoded amount.
    /// @return end Absolute position after the block.
    function unpackAssetAmount(uint abs, uint spec) internal pure returns (bytes32 asset, uint amount, uint end) {
        bytes32 value;
        (asset, value, end) = unpack64(abs, spec);
        amount = uint(value);
    }

    /// @notice Decode a spec-validated account, asset, and amount tuple.
    /// @param abs Absolute block position.
    /// @param spec Expected block specification.
    /// @return account Decoded account identifier.
    /// @return asset Decoded asset identifier.
    /// @return amount Decoded amount.
    /// @return end Absolute position after the block.
    function unpackAccountAmount(
        uint abs,
        uint spec
    ) internal pure returns (bytes32 account, bytes32 asset, uint amount, uint end) {
        bytes32 value;
        (account, asset, value, end) = unpack96(abs, spec);
        amount = uint(value);
    }

    /// @notice Decode a spec-validated host, asset, and amount tuple.
    /// @param abs Absolute block position.
    /// @param spec Expected block specification.
    /// @return host Decoded host identifier.
    /// @return asset Decoded asset identifier.
    /// @return amount Decoded amount.
    /// @return end Absolute position after the block.
    function unpackHostAmount(
        uint abs,
        uint spec
    ) internal pure returns (uint host, bytes32 asset, uint amount, uint end) {
        bytes32 value;
        bytes32 raw;
        (raw, asset, value, end) = unpack96(abs, spec);
        host = uint(raw);
        amount = uint(value);
    }

    /// @notice Decode a spec-validated host, account, and asset tuple.
    /// @param abs Absolute block position.
    /// @param spec Expected block specification.
    /// @return host Decoded host identifier.
    /// @return account Decoded account identifier.
    /// @return asset Decoded asset identifier.
    /// @return end Absolute position after the block.
    function unpackHostAccountAsset(
        uint abs,
        uint spec
    ) internal pure returns (uint host, bytes32 account, bytes32 asset, uint end) {
        bytes32 raw;
        (raw, account, asset, end) = unpack96(abs, spec);
        host = uint(raw);
    }

    /// @notice Decode a spec-validated transaction tuple.
    /// @param abs Absolute block position.
    /// @param spec Expected block specification.
    /// @return from Decoded debit account.
    /// @return to Decoded credit account.
    /// @return asset Decoded asset identifier.
    /// @return amount Decoded transaction amount.
    /// @return end Absolute position after the block.
    function unpackTransaction(
        uint abs,
        uint spec
    ) internal pure returns (bytes32 from, bytes32 to, bytes32 asset, uint amount, uint end) {
        bytes32 value;
        (from, to, asset, value, end) = unpack128(abs, spec);
        amount = uint(value);
    }

    // Fixed-width block unpackers

    /// @dev The fixed-width decoders below validate only the block key and
    /// payload length. Callers must ensure the complete block lies within
    /// their logical calldata region.

    // One-word payloads

    /// @notice Decode a low-level fixed-width ACCOUNT block at `abs`.
    /// @param abs Absolute block position.
    /// @return account Decoded account identifier.
    function unpackAccount(uint abs) internal pure returns (bytes32 account) {
        uint64 head;
        assembly ("memory-safe") {
            head := shr(192, calldataload(abs))
            account := calldataload(add(abs, 0x08))
        }
        if (head != Headers.Account) revert InvalidBlock();
    }

    /// @notice Decode a low-level fixed-width ASSET block at `abs`.
    /// @param abs Absolute block position.
    /// @return asset Decoded asset identifier.
    function unpackAsset(uint abs) internal pure returns (bytes32 asset) {
        uint64 head;
        assembly ("memory-safe") {
            head := shr(192, calldataload(abs))
            asset := calldataload(add(abs, 0x08))
        }
        if (head != Headers.Asset) revert InvalidBlock();
    }

    /// @notice Decode a low-level fixed-width NODE block at `abs`.
    /// @param abs Absolute block position.
    /// @return node Decoded node identifier.
    function unpackNode(uint abs) internal pure returns (uint node) {
        uint64 head;
        assembly ("memory-safe") {
            head := shr(192, calldataload(abs))
            node := calldataload(add(abs, 0x08))
        }
        if (head != Headers.Node) revert InvalidBlock();
    }

    /// @notice Decode a low-level fixed-width STATUS block at `abs`.
    /// @param abs Absolute block position.
    /// @return code Decoded status code.
    function unpackStatus(uint abs) internal pure returns (uint code) {
        uint64 head;
        assembly ("memory-safe") {
            head := shr(192, calldataload(abs))
            code := calldataload(add(abs, 0x08))
        }
        if (head != Headers.Status) revert InvalidBlock();
    }

    // Two-word payloads

    /// @notice Decode a low-level fixed-width AMOUNT block at `abs`.
    /// @param abs Absolute block position.
    /// @return asset Decoded asset identifier.
    /// @return amount Decoded amount.
    function unpackAmount(uint abs) internal pure returns (bytes32 asset, uint amount) {
        uint64 head;
        assembly ("memory-safe") {
            head := shr(192, calldataload(abs))
            asset := calldataload(add(abs, 0x08))
            amount := calldataload(add(abs, 0x28))
        }
        if (head != Headers.Amount) revert InvalidBlock();
    }

    /// @notice Decode a low-level fixed-width BALANCE block at `abs`.
    /// @param abs Absolute block position.
    /// @return asset Decoded asset identifier.
    /// @return amount Decoded balance.
    function unpackBalance(uint abs) internal pure returns (bytes32 asset, uint amount) {
        uint64 head;
        assembly ("memory-safe") {
            head := shr(192, calldataload(abs))
            asset := calldataload(add(abs, 0x08))
            amount := calldataload(add(abs, 0x28))
        }
        if (head != Headers.Balance) revert InvalidBlock();
    }

    /// @notice Decode a low-level fixed-width ASSET_LIABILITY block at `abs`.
    /// @param abs Absolute block position.
    /// @return asset Decoded asset identifier.
    /// @return liability Decoded liability identifier.
    function unpackAssetLiability(uint abs) internal pure returns (bytes32 asset, bytes32 liability) {
        uint64 head;
        assembly ("memory-safe") {
            head := shr(192, calldataload(abs))
            asset := calldataload(add(abs, 0x08))
            liability := calldataload(add(abs, 0x28))
        }
        if (head != Headers.AssetLiability) revert InvalidBlock();
    }

    /// @notice Decode a low-level fixed-width ACCOUNT_ASSET block at `abs`.
    /// @param abs Absolute block position.
    /// @return account Decoded account identifier.
    /// @return asset Decoded asset identifier.
    function unpackAccountAsset(uint abs) internal pure returns (bytes32 account, bytes32 asset) {
        uint64 head;
        assembly ("memory-safe") {
            head := shr(192, calldataload(abs))
            account := calldataload(add(abs, 0x08))
            asset := calldataload(add(abs, 0x28))
        }
        if (head != Headers.AccountAsset) revert InvalidBlock();
    }

    // Three-word payloads

    /// @notice Decode a low-level fixed-width BOOTSTRAP block at `abs`.
    /// @param abs Absolute block position.
    /// @return asset Decoded asset identifier.
    /// @return amount Decoded balance amount.
    /// @return budget Decoded native-value budget contribution.
    function unpackBootstrap(uint abs) internal pure returns (bytes32 asset, uint amount, uint budget) {
        uint64 head;
        assembly ("memory-safe") {
            head := shr(192, calldataload(abs))
            asset := calldataload(add(abs, 0x08))
            amount := calldataload(add(abs, 0x28))
            budget := calldataload(add(abs, 0x48))
        }
        if (head != Headers.Bootstrap) revert InvalidBlock();
    }

    /// @notice Decode a low-level fixed-width ALLOCATION block at `abs`.
    /// @param abs Absolute block position.
    /// @return host Decoded host identifier.
    /// @return asset Decoded asset identifier.
    /// @return amount Decoded allocation.
    function unpackAllocation(uint abs) internal pure returns (uint host, bytes32 asset, uint amount) {
        uint64 head;
        assembly ("memory-safe") {
            head := shr(192, calldataload(abs))
            host := calldataload(add(abs, 0x08))
            asset := calldataload(add(abs, 0x28))
            amount := calldataload(add(abs, 0x48))
        }
        if (head != Headers.Allocation) revert InvalidBlock();
    }

    /// @notice Decode a low-level fixed-width ALLOWANCE block at `abs`.
    /// @param abs Absolute block position.
    /// @return host Decoded host identifier.
    /// @return asset Decoded asset identifier.
    /// @return amount Decoded allowance.
    function unpackAllowance(uint abs) internal pure returns (uint host, bytes32 asset, uint amount) {
        uint64 head;
        assembly ("memory-safe") {
            head := shr(192, calldataload(abs))
            host := calldataload(add(abs, 0x08))
            asset := calldataload(add(abs, 0x28))
            amount := calldataload(add(abs, 0x48))
        }
        if (head != Headers.Allowance) revert InvalidBlock();
    }

    /// @notice Decode a low-level fixed-width CUSTODY block at `abs`.
    /// @param abs Absolute block position.
    /// @return host Decoded host identifier.
    /// @return asset Decoded asset identifier.
    /// @return amount Decoded custody amount.
    function unpackCustody(uint abs) internal pure returns (uint host, bytes32 asset, uint amount) {
        uint64 head;
        assembly ("memory-safe") {
            head := shr(192, calldataload(abs))
            host := calldataload(add(abs, 0x08))
            asset := calldataload(add(abs, 0x28))
            amount := calldataload(add(abs, 0x48))
        }
        if (head != Headers.Custody) revert InvalidBlock();
    }

    /// @notice Decode a low-level fixed-width ACCOUNT_AMOUNT block at `abs`.
    /// @param abs Absolute block position.
    /// @return account Decoded account identifier.
    /// @return asset Decoded asset identifier.
    /// @return amount Decoded amount.
    function unpackAccountAmount(uint abs) internal pure returns (bytes32 account, bytes32 asset, uint amount) {
        uint64 head;
        assembly ("memory-safe") {
            head := shr(192, calldataload(abs))
            account := calldataload(add(abs, 0x08))
            asset := calldataload(add(abs, 0x28))
            amount := calldataload(add(abs, 0x48))
        }
        if (head != Headers.AccountAmount) revert InvalidBlock();
    }

    /// @notice Decode a low-level fixed-width HOST_AMOUNT block at `abs`.
    /// @param abs Absolute block position.
    /// @return host Decoded host identifier.
    /// @return asset Decoded asset identifier.
    /// @return amount Decoded amount.
    function unpackHostAmount(uint abs) internal pure returns (uint host, bytes32 asset, uint amount) {
        uint64 head;
        assembly ("memory-safe") {
            head := shr(192, calldataload(abs))
            host := calldataload(add(abs, 0x08))
            asset := calldataload(add(abs, 0x28))
            amount := calldataload(add(abs, 0x48))
        }
        if (head != Headers.HostAmount) revert InvalidBlock();
    }

    /// @notice Decode a low-level fixed-width HOST_ACCOUNT_ASSET block at `abs`.
    /// @param abs Absolute block position.
    /// @return host Decoded host identifier.
    /// @return account Decoded account identifier.
    /// @return asset Decoded asset identifier.
    function unpackHostAccountAsset(uint abs) internal pure returns (uint host, bytes32 account, bytes32 asset) {
        uint64 head;
        assembly ("memory-safe") {
            head := shr(192, calldataload(abs))
            host := calldataload(add(abs, 0x08))
            account := calldataload(add(abs, 0x28))
            asset := calldataload(add(abs, 0x48))
        }
        if (head != Headers.HostAccountAsset) revert InvalidBlock();
    }

    /// @notice Decode a LIMITS block at an in-bounds absolute calldata position.
    /// @param abs Absolute block position.
    /// @return limits Packed minimum asset amount (high 128 bits) and maximum debt (low 128 bits).
    function unpackLimits(uint abs) internal pure returns (uint limits) {
        uint64 head;
        assembly ("memory-safe") {
            head := shr(192, calldataload(abs))
            limits := calldataload(add(abs, 0x08))
        }
        if (head != Headers.Limits) revert InvalidBlock();
    }

    // Quote and position payloads

    /// @notice Decode a QUOTE at an in-bounds absolute calldata position.
    /// Exact identifiers precede packed minimum amount and maximum debt limits.
    function unpackQuote(
        uint abs
    ) internal pure returns (bytes32 asset, bytes32 liability, bytes32 counterparty, uint limits) {
        uint64 head;
        assembly ("memory-safe") {
            head := shr(192, calldataload(abs))
            asset := calldataload(add(abs, 0x08))
            liability := calldataload(add(abs, 0x28))
            counterparty := calldataload(add(abs, 0x48))
            limits := calldataload(add(abs, 0x68))
        }
        if (head != Headers.Quote) revert InvalidBlock();
    }

    /// @notice Decode a low-level fixed-width POSITION block at `abs`.
    /// @param abs Absolute block position.
    /// @return asset Decoded asset-side identifier.
    /// @return amount Decoded asset-side quantity.
    /// @return liability Decoded liability-side identifier.
    /// @return debt Decoded liability-side debt.
    /// @return counterparty Decoded settlement counterparty.
    function unpackPosition(
        uint abs
    ) internal pure returns (bytes32 asset, uint amount, bytes32 liability, uint debt, bytes32 counterparty) {
        uint64 head;
        assembly ("memory-safe") {
            head := shr(192, calldataload(abs))
            asset := calldataload(add(abs, 0x08))
            amount := calldataload(add(abs, 0x28))
            liability := calldataload(add(abs, 0x48))
            debt := calldataload(add(abs, 0x68))
            counterparty := calldataload(add(abs, 0x88))
        }
        if (head != Headers.Position) revert InvalidBlock();
    }

    /// @notice Decode a POSITION and enforce its paired LIMITS directly in calldata.
    /// @dev DANGER: Unchecked calldata reads. The caller must ensure both complete
    /// blocks are in bounds. Validates exact headers before quantity bounds.
    /// Does not validate account or asset identifiers or advance either stream.
    /// @param pos Absolute calldata position of the POSITION block.
    /// @param lim Absolute calldata position of the LIMITS block.
    /// @return position Decoded position satisfying the inclusive packed limits.
    function unpackLimitedPosition(uint pos, uint lim) internal pure returns (Position memory position) {
        uint64 poshead;
        uint64 limitshead;
        bool outside;
        assembly ("memory-safe") {
            poshead := shr(192, calldataload(pos))
            limitshead := shr(192, calldataload(lim))
            let limits := calldataload(add(lim, 0x08))
            let amount := calldataload(add(pos, 0x28))
            let debt := calldataload(add(pos, 0x68))
            outside := or(lt(amount, shr(128, limits)), gt(debt, and(limits, 0xffffffffffffffffffffffffffffffff)))
        }
        if (poshead != Headers.Position || limitshead != Headers.Limits) revert InvalidBlock();
        if (outside) revert OutOfRange();
        assembly ("memory-safe") {
            // POSITION's five payload words match its memory struct layout.
            calldatacopy(position, add(pos, 0x08), 0xa0)
        }
    }

    /// @notice Decode a low-level fixed-width HOST_ASSET block at `abs`.
    /// @param abs Absolute block position.
    /// @return host Decoded host identifier.
    /// @return asset Decoded asset identifier.
    function unpackHostAsset(uint abs) internal pure returns (uint host, bytes32 asset) {
        uint64 head;
        assembly ("memory-safe") {
            head := shr(192, calldataload(abs))
            host := calldataload(add(abs, 0x08))
            asset := calldataload(add(abs, 0x28))
        }
        if (head != Headers.HostAsset) revert InvalidBlock();
    }

    /// @notice Decode a low-level fixed-width TRANSACTION block at `abs`.
    /// @param abs Absolute block position.
    /// @return from Decoded debit account.
    /// @return to Decoded credit account.
    /// @return asset Decoded asset identifier.
    /// @return amount Decoded transaction amount.
    function unpackTransaction(uint abs) internal pure returns (bytes32 from, bytes32 to, bytes32 asset, uint amount) {
        uint64 head;
        assembly ("memory-safe") {
            head := shr(192, calldataload(abs))
            from := calldataload(add(abs, 0x08))
            to := calldataload(add(abs, 0x28))
            asset := calldataload(add(abs, 0x48))
            amount := calldataload(add(abs, 0x68))
        }
        if (head != Headers.Transaction) revert InvalidBlock();
    }

    /// @notice Decode a low-level fixed-width HOST_ACCOUNT_AMOUNT block at `abs`.
    /// @param abs Absolute block position.
    /// @return host Decoded host identifier.
    /// @return account Decoded account identifier.
    /// @return asset Decoded asset identifier.
    /// @return amount Decoded amount.
    function unpackHostAccountAmount(
        uint abs
    ) internal pure returns (uint host, bytes32 account, bytes32 asset, uint amount) {
        uint64 head;
        assembly ("memory-safe") {
            head := shr(192, calldataload(abs))
            host := calldataload(add(abs, 0x08))
            account := calldataload(add(abs, 0x28))
            asset := calldataload(add(abs, 0x48))
            amount := calldataload(add(abs, 0x68))
        }
        if (head != Headers.HostAccountAmount) revert InvalidBlock();
    }

    // Dynamic leaf blocks

    /// @notice Decode one LIST payload and its absolute end position.
    /// @param abs Absolute block position.
    /// @return value Decoded list payload.
    /// @return end Absolute position after the block.
    function unpackList(uint abs) internal pure returns (bytes calldata value, uint end) {
        uint key;
        uint len;
        assembly ("memory-safe") {
            let word := calldataload(abs)
            key := shr(224, word)
            len := and(shr(192, word), 0xffffffff)
            value.offset := add(abs, 0x08)
            value.length := len
        }
        if (key != uint32(Keys.List)) revert InvalidBlock();
        // len came from uint32: adding the header cannot overflow. One
        // checked addition retains the original absolute-position overflow panic.
        unchecked {
            len += Sizes.Header;
        }
        end = abs + len;
    }

    /// @notice Decode one BYTES payload and its absolute end position.
    /// @param abs Absolute block position.
    /// @return value Decoded byte payload.
    /// @return end Absolute position after the block.
    function unpackBytes(uint abs) internal pure returns (bytes calldata value, uint end) {
        uint key;
        uint len;
        assembly ("memory-safe") {
            let word := calldataload(abs)
            key := shr(224, word)
            len := and(shr(192, word), 0xffffffff)
            value.offset := add(abs, 0x08)
            value.length := len
        }
        if (key != uint32(Keys.Bytes)) revert InvalidBlock();
        // len came from uint32: adding the header cannot overflow. One
        // checked addition retains the original absolute-position overflow panic.
        unchecked {
            len += Sizes.Header;
        }
        end = abs + len;
    }

    /// @notice Decode one STRING payload and its absolute end position.
    /// @param abs Absolute block position.
    /// @return value Decoded string bytes.
    /// @return end Absolute position after the block.
    function unpackString(uint abs) internal pure returns (bytes calldata value, uint end) {
        uint key;
        uint len;
        assembly ("memory-safe") {
            let word := calldataload(abs)
            key := shr(224, word)
            len := and(shr(192, word), 0xffffffff)
            value.offset := add(abs, 0x08)
            value.length := len
        }
        if (key != uint32(Keys.String)) revert InvalidBlock();
        // len came from uint32: adding the header cannot overflow. One
        // checked addition retains the original absolute-position overflow panic.
        unchecked {
            len += Sizes.Header;
        }
        end = abs + len;
    }

    // Composite blocks

    /// @dev Validate the final BYTES child against the parent's known end.
    /// Called only after validating a nonzero outer key. Fixed offsets are still
    /// checked by the caller; a matching child header also implies its position
    /// is in calldata. No logical-region bounds are added here.
    function unpackTailBytes(uint abs, uint end) private pure returns (bytes calldata value) {
        uint byteskey = uint32(Keys.Bytes);
        bool valid;
        assembly ("memory-safe") {
            let body := add(abs, 8)
            let len := sub(end, body)
            valid := and(iszero(gt(len, 0xffffffff)), eq(shr(192, calldataload(abs)), or(shl(32, byteskey), len)))
            value.offset := body
            value.length := len
        }
        if (!valid) revert InvalidBlock();
    }

    /// @dev STRING variant of unpackTailBytes. For SCHEMA, end excludes the
    /// trailing name word; an underflowed end fails the uint32 length check.
    function unpackTailString(uint abs, uint end) private pure returns (bytes calldata value) {
        uint stringkey = uint32(Keys.String);
        bool valid;
        assembly ("memory-safe") {
            let body := add(abs, 8)
            let len := sub(end, body)
            valid := and(iszero(gt(len, 0xffffffff)), eq(shr(192, calldataload(abs)), or(shl(32, stringkey), len)))
            value.offset := body
            value.length := len
        }
        if (!valid) revert InvalidBlock();
    }

    // One fixed word

    /// @notice Decode one ANNOTATION block and its nested block stream.
    /// @param abs Absolute block position.
    /// @return entity Decoded entity identifier.
    /// @return stream Decoded annotation block stream.
    /// @return end Absolute position after the block.
    function unpackAnnotation(uint abs) internal pure returns (uint entity, bytes calldata stream, uint end) {
        uint limit;
        (abs, limit) = enter(abs, Keys.Annotation);
        assembly ("memory-safe") {
            entity := calldataload(abs)
        }
        stream = unpackTailBytes(abs + 32, limit);
        end = limit;
    }

    /// @notice Decode one CONTEXT block and all nested byte blocks.
    /// @param abs Absolute block position.
    /// @return account Decoded account identifier.
    /// @return state Decoded state payload.
    /// @return input Decoded input payload.
    /// @return end Absolute position after the block.
    function unpackContext(
        uint abs
    ) internal pure returns (bytes32 account, bytes calldata state, bytes calldata input, uint end) {
        uint limit;
        (abs, limit) = enter(abs, Keys.Context);
        assembly ("memory-safe") {
            account := calldataload(abs)
        }
        (state, end) = unpackBytes(abs + 32);
        input = unpackTailBytes(end, limit);
        end = limit;
    }

    // Two fixed words

    /// @notice Decode one STEP block and its nested input.
    /// @param abs Absolute block position.
    /// @return cmd Decoded command identifier.
    /// @return value Decoded native value.
    /// @return input Decoded command input.
    /// @return end Absolute position after the block.
    function unpackStep(uint abs) internal pure returns (uint cmd, uint value, bytes calldata input, uint end) {
        uint limit;
        (abs, limit) = enter(abs, Keys.Step);
        assembly ("memory-safe") {
            cmd := calldataload(abs)
            value := calldataload(add(abs, 0x20))
        }
        input = unpackTailBytes(abs + 64, limit);
        end = limit;
    }

    /// @notice Decode one CALL block and its nested payload.
    /// @param abs Absolute block position.
    /// @return target Decoded call target.
    /// @return resources Decoded packed resources.
    /// @return payload Decoded call payload.
    /// @return end Absolute position after the block.
    function unpackCall(
        uint abs
    ) internal pure returns (uint target, uint resources, bytes calldata payload, uint end) {
        uint limit;
        (abs, limit) = enter(abs, Keys.Call);
        assembly ("memory-safe") {
            target := calldataload(abs)
            resources := calldataload(add(abs, 0x20))
        }
        payload = unpackTailBytes(abs + 64, limit);
        end = limit;
    }

    /// @notice Decode one RELAY block and its nested input and continuation.
    /// @param abs Absolute block position.
    /// @return input Decoded command-specific input.
    /// @return steps Decoded remaining pipeline steps.
    /// @return end Absolute position after the block.
    function unpackRelay(uint abs) internal pure returns (bytes calldata input, bytes calldata steps, uint end) {
        uint limit;
        (abs, limit) = enter(abs, Keys.Relay);
        (input, abs) = unpackBytes(abs);
        steps = unpackTailBytes(abs, limit);
        end = limit;
    }

    /// @notice Decode one DISPATCH block and its nested payload.
    /// @param abs Absolute block position.
    /// @return portal Decoded destination portal.
    /// @return resources Decoded packed resources.
    /// @return payload Decoded dispatch payload.
    /// @return end Absolute position after the block.
    function unpackDispatch(
        uint abs
    ) internal pure returns (uint portal, uint resources, bytes calldata payload, uint end) {
        uint limit;
        (abs, limit) = enter(abs, Keys.Dispatch);
        assembly ("memory-safe") {
            portal := calldataload(abs)
            resources := calldataload(add(abs, 0x20))
        }
        payload = unpackTailBytes(abs + 64, limit);
        end = limit;
    }

    /// @notice Decode one LABEL block and its nested name.
    /// @param abs Absolute block position.
    /// @return namespace Decoded label namespace.
    /// @return name Decoded label text.
    /// @return end Absolute position after the block.
    function unpackLabel(uint abs) internal pure returns (bytes32 namespace, string memory name, uint end) {
        uint limit;
        (abs, limit) = enter(abs, Keys.Label);
        assembly ("memory-safe") {
            namespace := calldataload(abs)
        }
        bytes calldata value;
        value = unpackTailString(abs + 32, limit);
        end = limit;
        name = string(value);
    }

    /// @notice Decode one SCHEMA block and its nested body.
    /// @param abs Absolute block position.
    /// @return spec Decoded block specification.
    /// @return body Decoded schema body.
    /// @return name Decoded schema name.
    /// @return end Absolute position after the block.
    function unpackSchema(uint abs) internal pure returns (uint spec, string memory body, bytes32 name, uint end) {
        uint limit;
        (abs, limit) = enter(abs, Keys.Schema);
        assembly ("memory-safe") {
            spec := calldataload(abs)
        }
        bytes calldata value;
        // The final word follows the STRING child. A too-short parent is
        // rejected by unpackTailString, including subtraction underflow.
        unchecked {
            end = limit - 32;
        }
        value = unpackTailString(abs + 32, end);
        assembly ("memory-safe") {
            name := calldataload(end)
        }
        end = limit;
        body = string(value);
    }

    // Three fixed words

    /// @notice Decode one RECOVER block and its nested witness.
    /// @param abs Absolute block position.
    /// @return handler Decoded recovery handler.
    /// @return resources Decoded packed resources.
    /// @return key Decoded recovery key.
    /// @return witness Decoded recovery witness.
    /// @return end Absolute position after the block.
    function unpackRecover(
        uint abs
    ) internal pure returns (uint handler, uint resources, bytes32 key, bytes calldata witness, uint end) {
        uint limit;
        (abs, limit) = enter(abs, Keys.Recover);
        assembly ("memory-safe") {
            handler := calldataload(abs)
            resources := calldataload(add(abs, 0x20))
            key := calldataload(add(abs, 0x40))
        }
        witness = unpackTailBytes(abs + 96, limit);
        end = limit;
    }

    // -------------------------------------------------------------------------
    // Block factory helpers
    // -------------------------------------------------------------------------

    /// @dev Allocate an exact-length result with one trailing scratch word for
    /// unchecked writers that store an eight-byte header with `mstore`.
    function allocate(uint len) private pure returns (bytes memory value) {
        // Every factory overwrites the complete logical result. Only initialize
        // padding and the trailing scratch word, including when memory is dirty.
        // Factory lengths are bounded by uint32 (plus a fixed header).
        assembly ("memory-safe") {
            value := mload(0x40)
            let padded := and(add(len, 31), not(31))
            let tail := add(add(value, 0x20), padded)
            mstore(0x40, add(tail, 0x20))
            mstore(value, len)
            mstore(add(add(value, 0x20), len), 0)
        }
    }

    // Generic factories

    /// @notice Encode an empty block.
    /// @param key Block type key.
    /// @return value Encoded empty block header.
    function createEmpty(bytes4 key) internal pure returns (bytes memory value) {
        value = allocate(Sizes.Header);
        writeEmpty(value, 0, key);
    }

    /// @notice Encode a block with a raw payload.
    /// @param key Block type key.
    /// @param payload Raw payload bytes.
    /// @return value Encoded block bytes.
    function create(bytes4 key, bytes memory payload) internal pure returns (bytes memory value) {
        uint len = max32(payload.length);
        value = allocate(Sizes.Header + len);
        writeSized(value, 0, key, payload, len);
    }

    /// @notice Encode a block by copying its raw payload from calldata.
    function createCopy(bytes4 key, bytes calldata payload) internal pure returns (bytes memory value) {
        uint len = max32(payload.length);
        value = allocate(Sizes.Header + len);
        copySized(value, 0, key, payload, len);
    }

    // Dynamic leaf factories

    /// @notice Encode a LIST block.
    function createList(bytes memory value) internal pure returns (bytes memory blockdata) {
        uint len = max32(value.length);
        blockdata = allocate(Sizes.Header + len);
        writeList(blockdata, 0, value);
    }

    /// @notice Encode a LIST block by copying its payload from calldata.
    function createListCopy(bytes calldata value) internal pure returns (bytes memory blockdata) {
        uint len = max32(value.length);
        blockdata = allocate(Sizes.Header + len);
        copySized(blockdata, 0, Keys.List, value, len);
    }

    /// @notice Encode a BYTES block with a raw payload.
    /// @param value Raw payload bytes.
    /// @return blockdata Encoded BYTES block bytes.
    function createBytes(bytes memory value) internal pure returns (bytes memory blockdata) {
        uint len = max32(value.length);
        blockdata = allocate(Sizes.Header + len);
        writeBytes(blockdata, 0, value);
    }

    /// @notice Encode a BYTES block by copying its payload from calldata.
    function createBytesCopy(bytes calldata value) internal pure returns (bytes memory blockdata) {
        uint len = max32(value.length);
        blockdata = allocate(Sizes.Header + len);
        copySized(blockdata, 0, Keys.Bytes, value, len);
    }

    /// @notice Encode a STRING block with a UTF-8 payload.
    /// @param value String payload.
    /// @return blockdata Encoded STRING block bytes.
    function createString(string memory value) internal pure returns (bytes memory blockdata) {
        uint len = max32(bytes(value).length);
        blockdata = allocate(Sizes.Header + len);
        writeString(blockdata, 0, value);
    }

    /// @notice Encode a STRING block by copying its payload from calldata.
    function createStringCopy(string calldata value) internal pure returns (bytes memory blockdata) {
        uint len = max32(bytes(value).length);
        blockdata = allocate(Sizes.Header + len);
        copySized(blockdata, 0, Keys.String, bytes(value), len);
    }

    // Annotation factories

    /// @notice Encode a LABEL block.
    /// @param namespace Label namespace.
    /// @param name Label text.
    /// @return value Encoded LABEL block bytes.
    function createLabel(bytes32 namespace, string memory name) internal pure returns (bytes memory value) {
        uint len = max32(Sizes.B32 + bytes(name).length);
        value = allocate(Sizes.Header + len);
        writeLabelAllocated(value, namespace, name);
    }

    /// @notice Encode an ACTION annotation block.
    /// @param actionid Canonical semantic action identifier.
    /// @return value Encoded ACTION block bytes.
    function createAction(uint actionid) internal pure returns (bytes memory value) {
        value = allocate(Sizes.B32);
        write32(value, 0, Keys.Action, bytes32(actionid));
    }

    /// @notice Encode a COUNTERPARTY annotation block.
    /// @param account Counterparty account ID, or zero for Rootzero.
    /// @return value Encoded COUNTERPARTY block bytes.
    function createCounterparty(bytes32 account) internal pure returns (bytes memory value) {
        value = allocate(Sizes.B32);
        write32(value, 0, Keys.Counterparty, account);
    }

    /// @notice Encode a SCHEMA block.
    /// @param spec Block specification.
    /// @param body Schema body.
    /// @return value Encoded SCHEMA block bytes.
    function createSchema(uint spec, string memory body) internal pure returns (bytes memory value) {
        return createSchema(spec, body, bytes32(0));
    }

    /// @notice Encode a named SCHEMA block.
    /// @param spec Block specification.
    /// @param body Schema body.
    /// @param name Schema name.
    /// @return value Encoded SCHEMA block bytes.
    function createSchema(uint spec, string memory body, bytes32 name) internal pure returns (bytes memory value) {
        uint len = max32(Sizes.B64 + bytes(body).length);
        value = allocate(Sizes.Header + len);
        writeSchemaAllocated(value, spec, body, name);
    }

    // Fixed-width factories

    /// @notice Encode a BOOTSTRAP block.
    /// @param asset Asset identifier.
    /// @param amount Balance amount to source.
    /// @param budget Native-value budget to source.
    /// @return value Encoded BOOTSTRAP block bytes.
    function createBootstrap(bytes32 asset, uint amount, uint budget) internal pure returns (bytes memory value) {
        value = allocate(Sizes.Bootstrap);
        writeBootstrap(value, 0, asset, amount, budget);
    }

    /// @notice Encode an AMOUNT block.
    /// @param asset Asset identifier.
    /// @param amount Token amount.
    /// @return value Encoded AMOUNT block bytes.
    function createAmount(bytes32 asset, uint amount) internal pure returns (bytes memory value) {
        value = allocate(Sizes.Amount);
        writeAmount(value, 0, asset, amount);
    }

    /// @notice Encode a BALANCE block.
    /// @param asset Asset identifier.
    /// @param amount Token amount.
    /// @return value Encoded BALANCE block bytes.
    function createBalance(bytes32 asset, uint amount) internal pure returns (bytes memory value) {
        value = allocate(Sizes.Balance);
        writeBalance(value, 0, asset, amount);
    }

    /// @notice Encode an ASSET_LIABILITY block.
    /// @param asset Asset identifier.
    /// @param liability Liability identifier.
    /// @return value Encoded ASSET_LIABILITY block bytes.
    function createAssetLiability(bytes32 asset, bytes32 liability) internal pure returns (bytes memory value) {
        value = allocate(Sizes.B64);
        writeAssetLiability(value, 0, asset, liability);
    }

    /// @notice Encode a CUSTODY block.
    /// @param host Host node ID holding the custody.
    /// @param asset Asset identifier.
    /// @param amount Token amount.
    /// @return value Encoded CUSTODY block bytes.
    function createCustody(uint host, bytes32 asset, uint amount) internal pure returns (bytes memory value) {
        value = allocate(Sizes.Custody);
        writeCustody(value, 0, host, asset, amount);
    }

    /// @notice Encode a LIMITS block with minimum amount and maximum debt.
    /// @param limits Packed minimum asset amount (high 128 bits) and maximum debt (low 128 bits).
    /// @return value Encoded LIMITS block.
    function createLimits(uint limits) internal pure returns (bytes memory value) {
        value = allocate(Sizes.Limits);
        writeLimits(value, 0, limits);
    }

    /// @notice Encode a QUOTE block.
    function createQuote(
        bytes32 asset,
        bytes32 liability,
        bytes32 counterparty,
        uint limits
    ) internal pure returns (bytes memory value) {
        value = allocate(Sizes.Quote);
        writeQuote(value, 0, asset, liability, counterparty, limits);
    }

    /// @notice Encode a POSITION block.
    /// @param asset Identifier for the asset side.
    /// @param amount Quantity on the asset side.
    /// @param liability Identifier for the liability side.
    /// @param debt Quantity owed on the liability side.
    /// @param counterparty Settlement counterparty: Rootzero (zero) or an account ID, including a host account.
    /// @return value Encoded POSITION block bytes.
    function createPosition(
        bytes32 asset,
        uint amount,
        bytes32 liability,
        uint debt,
        bytes32 counterparty
    ) internal pure returns (bytes memory value) {
        value = allocate(Sizes.Position);
        writePosition(value, 0, asset, amount, liability, debt, counterparty);
    }

    /// @notice Encode a TRANSACTION block.
    /// @param from Source account identifier.
    /// @param to Destination account identifier.
    /// @param asset Asset identifier.
    /// @param amount Transfer amount.
    /// @return value Encoded TRANSACTION block bytes.
    function createTransaction(
        bytes32 from,
        bytes32 to,
        bytes32 asset,
        uint amount
    ) internal pure returns (bytes memory value) {
        value = allocate(Sizes.Transaction);
        writeTransaction(value, 0, from, to, asset, amount);
    }

    // Composite factories

    /// @notice Encode a STEP block.
    /// @param cmd Command identifier.
    /// @param value Native value assigned to the step.
    /// @param input Raw nested input payload.
    /// @return encoded Encoded STEP block bytes.
    function createStep(uint cmd, uint value, bytes memory input) internal pure returns (bytes memory encoded) {
        uint len = max32(Sizes.Step + input.length);
        encoded = allocate(len);
        writeCompositeAllocated(encoded, Keys.Step, cmd, value, input);
    }

    /// @notice Encode a STEP block by copying its nested input from calldata.
    function createStepCopy(uint cmd, uint value, bytes calldata input) internal pure returns (bytes memory encoded) {
        uint len = max32(Sizes.Step + input.length);
        encoded = allocate(len);
        copyCompositeAllocated(encoded, Keys.Step, cmd, value, input);
    }

    /// @notice Encode a CALL block.
    /// @param target Target node identifier.
    /// @param resources Packed resources assigned to the call.
    /// @param payload Raw calldata payload for the target.
    /// @return value Encoded CALL block bytes.
    function createCall(uint target, uint resources, bytes memory payload) internal pure returns (bytes memory value) {
        uint len = max32(Sizes.B64 + Sizes.Header + payload.length);
        value = allocate(len);
        writeCompositeAllocated(value, Keys.Call, target, resources, payload);
    }

    /// @notice Encode a CALL block by copying its nested payload from calldata.
    function createCallCopy(
        uint target,
        uint resources,
        bytes calldata payload
    ) internal pure returns (bytes memory value) {
        uint len = max32(Sizes.B64 + Sizes.Header + payload.length);
        value = allocate(len);
        copyCompositeAllocated(value, Keys.Call, target, resources, payload);
    }

    /// @notice Encode a RELAY block.
    /// @param input Nested command-specific input block stream.
    /// @param steps Nested remaining STEP block stream.
    /// @return value Encoded RELAY block bytes.
    function createRelay(bytes memory input, bytes memory steps) internal pure returns (bytes memory value) {
        uint len = max32(3 * Sizes.Header + input.length + steps.length);
        value = allocate(len);
        writeRelayAllocated(value, input, steps);
    }

    /// @notice Encode a RELAY block by copying its nested streams from calldata.
    function createRelayCopy(bytes calldata input, bytes calldata steps) internal pure returns (bytes memory value) {
        uint len = max32(3 * Sizes.Header + input.length + steps.length);
        value = allocate(len);
        copyRelayAllocated(value, input, steps);
    }

    /// @notice Encode a DISPATCH block.
    /// @param portal Destination portal implementation's host ID, passed through
    /// without semantic validation.
    /// @param resources Chain-specific resources for the destination dispatch.
    /// @param payload Encoded payload.
    /// @return value Encoded DISPATCH block bytes.
    function createDispatch(
        uint portal,
        uint resources,
        bytes memory payload
    ) internal pure returns (bytes memory value) {
        uint len = max32(Sizes.B64 + Sizes.Header + payload.length);
        value = allocate(len);
        writeCompositeAllocated(value, Keys.Dispatch, portal, resources, payload);
    }

    /// @notice Encode a DISPATCH block by copying its nested payload from calldata.
    function createDispatchCopy(
        uint portal,
        uint resources,
        bytes calldata payload
    ) internal pure returns (bytes memory value) {
        uint len = max32(Sizes.B64 + Sizes.Header + payload.length);
        value = allocate(len);
        copyCompositeAllocated(value, Keys.Dispatch, portal, resources, payload);
    }

    /// @notice Encode a CONTEXT block.
    function createContext(
        bytes32 account,
        bytes memory state,
        bytes memory input
    ) internal pure returns (bytes memory value) {
        uint len = max32(Sizes.B32 + 2 * Sizes.Header + state.length + input.length);
        value = allocate(len);
        writeContextAllocated(value, account, state, input);
    }

    /// @notice Encode a CONTEXT block by copying its nested streams from calldata.
    function createContextCopy(
        bytes32 account,
        bytes calldata state,
        bytes calldata input
    ) internal pure returns (bytes memory value) {
        uint len = max32(Sizes.B32 + 2 * Sizes.Header + state.length + input.length);
        value = allocate(len);
        copyContextAllocated(value, account, state, input);
    }

    /// @notice Encode a RECOVER block.
    function createRecover(
        uint handler,
        uint resources,
        bytes32 recoverykey,
        bytes memory witness
    ) internal pure returns (bytes memory value) {
        uint len = max32(Sizes.B96 + Sizes.Header + witness.length);
        value = allocate(len);
        writeRecoverAllocated(value, handler, resources, recoverykey, witness);
    }

    /// @notice Encode a RECOVER block by copying its nested witness from calldata.
    function createRecoverCopy(
        uint handler,
        uint resources,
        bytes32 recoverykey,
        bytes calldata witness
    ) internal pure returns (bytes memory value) {
        uint len = max32(Sizes.B96 + Sizes.Header + witness.length);
        value = allocate(len);
        copyRecoverAllocated(value, handler, resources, recoverykey, witness);
    }
}

/// @title Memory
/// @notice Fixed-stride decoding for homogeneous block streams held in memory.
/// @dev The unpackers are intentionally unchecked beyond their exact header
/// comparison. Callers must obtain bounds with `bounds`, advance by the matching
/// complete encoded block size, and stop at the returned end position.
library Memory {
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
        if (remainder != 0) revert Blocks.InvalidBlock();
    }

    /// @notice Decode a LIMITS block at an in-bounds absolute memory position.
    /// @param abs Absolute block position obtained from bounds.
    /// @return limits Packed minimum asset amount (high 128 bits) and maximum debt (low 128 bits).
    function unpackLimits(uint abs) internal pure returns (uint limits) {
        uint64 actual;
        assembly ("memory-safe") {
            actual := shr(192, mload(abs))
            limits := mload(add(abs, 0x08))
        }
        if (actual != Headers.Limits) revert Blocks.InvalidBlock();
    }

    /// @notice Decode a BALANCE block at an in-bounds absolute memory position.
    function unpackBalance(uint abs) internal pure returns (bytes32 asset, uint amount) {
        uint64 actual;
        assembly ("memory-safe") {
            actual := shr(192, mload(abs))
            asset := mload(add(abs, 0x08))
            amount := mload(add(abs, 0x28))
        }
        if (actual != Headers.Balance) revert Blocks.InvalidBlock();
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
        if (actual != Headers.Position) revert Blocks.InvalidBlock();
    }

    /// @notice Decode a POSITION struct at an in-bounds absolute memory position.
    /// @dev Validates the exact header and preserves all fields, including counterparty.
    function unpackPositionValue(uint abs) internal pure returns (Position memory value) {
        (value.asset, value.amount, value.liability, value.debt, value.counterparty) = unpackPosition(abs);
    }

    /// @notice Copy a memory POSITION after enforcing its paired calldata LIMITS.
    /// @dev DANGER: Unchecked reads. The caller must ensure the complete POSITION
    /// is in memory bounds and the complete LIMITS is in calldata bounds. Checks
    /// exact headers before quantity bounds. Does not validate identifiers or
    /// advance streams. The returned struct does not alias the source memory.
    /// @param pos Absolute memory position of the POSITION block.
    /// @param lim Absolute calldata position of the LIMITS block.
    /// @return position Independent position copy satisfying inclusive packed limits.
    function unpackLimitedPosition(uint pos, uint lim) internal pure returns (Position memory position) {
        uint64 poshead;
        uint64 limitshead;
        bool outside;
        assembly ("memory-safe") {
            poshead := shr(192, mload(pos))
            limitshead := shr(192, calldataload(lim))
            let limits := calldataload(add(lim, 0x08))
            let amount := mload(add(pos, 0x28))
            let debt := mload(add(pos, 0x68))
            outside := or(lt(amount, shr(128, limits)), gt(debt, and(limits, 0xffffffffffffffffffffffffffffffff)))
        }
        if (poshead != Headers.Position || limitshead != Headers.Limits) revert Blocks.InvalidBlock();
        if (outside) revert OutOfRange();
        assembly ("memory-safe") {
            mcopy(position, add(pos, 0x08), 0xa0)
        }
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
        if (actual != Headers.Transaction) revert Blocks.InvalidBlock();
    }
}
