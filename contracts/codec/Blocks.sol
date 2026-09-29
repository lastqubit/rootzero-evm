// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

import {Cursors} from "../utils/Cursors.sol";
import {Keys} from "./Keys.sol";
import {Headers} from "./Headers.sol";
import {Position, BalanceConstraints, PositionConstraints} from "../core/Types.sol";
import {INVALID_BLOCK, InvalidBlock, OutOfBounds, UnexpectedValue, OutOfRange} from "../utils/Errors.sol";

/// @title Blocks
/// @notice Calldata block helpers with bounded cursors and raw reads.
/// @dev A cursor stores absolute position in bits 0-31 and exclusive end in
/// bits 32-63. Selected ranges ignore source metadata and return clean cursors.
/// Stream unpackers return decoded values followed by an advanced source cursor preserving its
/// original end and metadata; decoded child ranges remain clean cursors. Exact selectors
/// require one block to fill the entire source range and return no next cursor.
/// Names use cur or a Cur suffix for packed cursors, and abs or an Abs suffix
/// for absolute calldata byte positions (including exclusive endAbs boundaries).
/// An absolute position never carries cursor metadata or an encoded end lane.
/// Callers must establish that the supplied range belongs to calldata.
/// These helpers validate logical containment, not the source's provenance.
/// take returns a complete block, unpack returns its payload, and prefix enter
/// returns the body position and remaining payload. Each also returns nextCur
/// for the caller to assign, without repeating bounds checks or reconstructing advancement.
/// The enclosing block's header/schema is checked before containment; prefix
/// lengths and nested child shapes are checked afterward. A full-width end
/// check proves header and payload containment, including for reversed ranges.
library Blocks {
    // Encoding and block creation belong to Encoder; memory execute helpers
    // belong to Execute.

    // -------------------------------------------------------------------------
    // Predicate primitives
    // -------------------------------------------------------------------------

    /// @notice Combine two predicates without short-circuit branching.
    /// @dev Both arguments are evaluated before this call. Use only when both
    /// expressions are safe to evaluate, such as reads of already validated fields.
    /// @param a First predicate.
    /// @param b Second predicate.
    /// @return result True if either predicate is true.
    function either(bool a, bool b) private pure returns (bool result) {
        assembly ("memory-safe") {
            result := or(a, b)
        }
    }

    // -------------------------------------------------------------------------
    // Absolute-position primitives, helpers, and stream scans
    // -------------------------------------------------------------------------

    /// @notice Read one word from an absolute calldata position without validation.
    /// @dev Performs no bounds, schema, or cursor checks. The caller must establish
    /// any required logical bounds before trusting the value. Reads past calldata
    /// use EVM zero-padding. Accepts the full uint256 position without narrowing.
    /// @param abs Absolute calldata byte position, not a packed cursor.
    /// @return value Raw 32-byte word starting at abs.
    function read32(uint abs) internal pure returns (bytes32 value) {
        assembly ("memory-safe") {
            value := calldataload(abs)
        }
    }

    /// @notice Read 1 byte from an absolute calldata position without validation.
    /// @dev Reuses read32 and retains its leading 1 byte. No bounds, schema,
    /// or cursor checks; the caller establishes logical bounds. Uses EVM zero-padding.
    /// @param abs Full-width absolute calldata byte position, not a packed cursor.
    /// @return value Raw 1-byte value starting at abs.
    function read1(uint abs) internal pure returns (bytes1 value) {
        return bytes1(read32(abs));
    }

    /// @notice Read 2 bytes from an absolute calldata position without validation.
    /// @dev Reuses read32 and retains its leading 2 bytes. No bounds, schema,
    /// or cursor checks; the caller establishes logical bounds. Uses EVM zero-padding.
    /// @param abs Full-width absolute calldata byte position, not a packed cursor.
    /// @return value Raw 2-byte value starting at abs.
    function read2(uint abs) internal pure returns (bytes2 value) {
        return bytes2(read32(abs));
    }

    /// @notice Read 4 bytes from an absolute calldata position without validation.
    /// @dev Reuses read32 and retains its leading 4 bytes. No bounds, schema,
    /// or cursor checks; the caller establishes logical bounds. Uses EVM zero-padding.
    /// @param abs Full-width absolute calldata byte position, not a packed cursor.
    /// @return value Raw 4-byte value starting at abs.
    function read4(uint abs) internal pure returns (bytes4 value) {
        return bytes4(read32(abs));
    }

    /// @notice Read 8 bytes from an absolute calldata position without validation.
    /// @dev Reuses read32 and retains its leading 8 bytes. No bounds, schema,
    /// or cursor checks; the caller establishes logical bounds. Uses EVM zero-padding.
    /// @param abs Full-width absolute calldata byte position, not a packed cursor.
    /// @return value Raw 8-byte value starting at abs.
    function read8(uint abs) internal pure returns (bytes8 value) {
        return bytes8(read32(abs));
    }

    /// @notice Read 16 bytes from an absolute calldata position without validation.
    /// @dev Reuses read32 and retains its leading 16 bytes. No bounds, schema,
    /// or cursor checks; the caller establishes logical bounds. Uses EVM zero-padding.
    /// @param abs Full-width absolute calldata byte position, not a packed cursor.
    /// @return value Raw 16-byte value starting at abs.
    function read16(uint abs) internal pure returns (bytes16 value) {
        return bytes16(read32(abs));
    }

    /// @notice Require the 1-byte value at abs to match value.
    /// @dev Unchecked absolute read; caller establishes logical bounds. Uses EVM
    /// zero-padding beyond calldata and reverts UnexpectedValue on mismatch.
    /// @param abs Full-width absolute calldata byte position, not a packed cursor.
    /// @param value Expected leading 1 bytes.
    function expect1(uint abs, bytes1 value) internal pure {
        if (read1(abs) != value) revert UnexpectedValue();
    }

    /// @notice Require the 2-byte value at abs to match value.
    /// @dev Unchecked absolute read; caller establishes logical bounds. Uses EVM
    /// zero-padding beyond calldata and reverts UnexpectedValue on mismatch.
    /// @param abs Full-width absolute calldata byte position, not a packed cursor.
    /// @param value Expected leading 2 bytes.
    function expect2(uint abs, bytes2 value) internal pure {
        if (read2(abs) != value) revert UnexpectedValue();
    }

    /// @notice Require the 4-byte value at abs to match value.
    /// @dev Unchecked absolute read; caller establishes logical bounds. Uses EVM
    /// zero-padding beyond calldata and reverts UnexpectedValue on mismatch.
    /// @param abs Full-width absolute calldata byte position, not a packed cursor.
    /// @param value Expected leading 4 bytes.
    function expect4(uint abs, bytes4 value) internal pure {
        if (read4(abs) != value) revert UnexpectedValue();
    }

    /// @notice Require the 8-byte value at abs to match value.
    /// @dev Unchecked absolute read; caller establishes logical bounds. Uses EVM
    /// zero-padding beyond calldata and reverts UnexpectedValue on mismatch.
    /// @param abs Full-width absolute calldata byte position, not a packed cursor.
    /// @param value Expected leading 8 bytes.
    function expect8(uint abs, bytes8 value) internal pure {
        if (read8(abs) != value) revert UnexpectedValue();
    }

    /// @notice Require the 16-byte value at abs to match value.
    /// @dev Unchecked absolute read; caller establishes logical bounds. Uses EVM
    /// zero-padding beyond calldata and reverts UnexpectedValue on mismatch.
    /// @param abs Full-width absolute calldata byte position, not a packed cursor.
    /// @param value Expected leading 16 bytes.
    function expect16(uint abs, bytes16 value) internal pure {
        if (read16(abs) != value) revert UnexpectedValue();
    }

    /// @notice Require the 32-byte value at abs to match value.
    /// @dev Unchecked absolute read; caller establishes logical bounds. Uses EVM
    /// zero-padding beyond calldata and reverts UnexpectedValue on mismatch.
    /// @param abs Full-width absolute calldata byte position, not a packed cursor.
    /// @param value Expected leading 32 bytes.
    function expect32(uint abs, bytes32 value) internal pure {
        if (read32(abs) != value) revert UnexpectedValue();
    }

    /// @notice Test whether the calldata word at abs is equal to value.
    /// @dev Unchecked absolute read with EVM zero-padding; caller owns logical bounds.
    /// Compares all 256 bits. The calldata word is the left operand.
    /// @param abs Full-width absolute calldata byte position, not a packed cursor.
    /// @param value Right-hand comparison value.
    /// @return result Comparison result; a failed comparison does not revert.
    function equal32(uint abs, bytes32 value) internal pure returns (bool result) {
        return read32(abs) == value;
    }

    /// @notice Test whether the calldata word at abs is less than value.
    /// @dev Unchecked absolute read with EVM zero-padding; caller owns logical bounds.
    /// Ordering is unsigned over all 256 bits. The calldata word is the left operand.
    /// @param abs Full-width absolute calldata byte position, not a packed cursor.
    /// @param value Right-hand comparison value.
    /// @return result Comparison result; a failed comparison does not revert.
    function lt32(uint abs, uint value) internal pure returns (bool result) {
        return uint(read32(abs)) < value;
    }

    /// @notice Test whether the calldata word at abs is greater than value.
    /// @dev Unchecked absolute read with EVM zero-padding; caller owns logical bounds.
    /// Ordering is unsigned over all 256 bits. The calldata word is the left operand.
    /// @param abs Full-width absolute calldata byte position, not a packed cursor.
    /// @param value Right-hand comparison value.
    /// @return result Comparison result; a failed comparison does not revert.
    function gt32(uint abs, uint value) internal pure returns (bool result) {
        return uint(read32(abs)) > value;
    }

    /// @notice Test whether the calldata word at abs is less than or equal to value.
    /// @dev Unchecked absolute read with EVM zero-padding; caller owns logical bounds.
    /// Ordering is unsigned over all 256 bits. The calldata word is the left operand.
    /// @param abs Full-width absolute calldata byte position, not a packed cursor.
    /// @param value Right-hand comparison value.
    /// @return result Comparison result; a failed comparison does not revert.
    function le32(uint abs, uint value) internal pure returns (bool result) {
        return !gt32(abs, value);
    }

    /// @notice Test whether the calldata word at abs is greater than or equal to value.
    /// @dev Unchecked absolute read with EVM zero-padding; caller owns logical bounds.
    /// Ordering is unsigned over all 256 bits. The calldata word is the left operand.
    /// @param abs Full-width absolute calldata byte position, not a packed cursor.
    /// @param value Right-hand comparison value.
    /// @return result Comparison result; a failed comparison does not revert.
    function ge32(uint abs, uint value) internal pure returns (bool result) {
        return !lt32(abs, value);
    }

    /// @notice Test whether the word at abs is equal to the word at otherAbs.
    /// @dev Both reads are unchecked and use EVM zero-padding. Caller owns both
    /// logical bounds. Equality compares all 256 bits.
    /// @param abs Full-width absolute position of the left operand.
    /// @param otherAbs Full-width absolute position of the right operand.
    /// @return result Comparison result; a failed comparison does not revert.
    function equalAt32(uint abs, uint otherAbs) internal pure returns (bool result) {
        return read32(abs) == read32(otherAbs);
    }

    /// @notice Test whether the word at abs is less than the word at otherAbs.
    /// @dev Both reads are unchecked and use EVM zero-padding. Caller owns both
    /// logical bounds. Ordering is unsigned over all 256 bits.
    /// @param abs Full-width absolute position of the left operand.
    /// @param otherAbs Full-width absolute position of the right operand.
    /// @return result Comparison result; a failed comparison does not revert.
    function ltAt32(uint abs, uint otherAbs) internal pure returns (bool result) {
        return uint(read32(abs)) < uint(read32(otherAbs));
    }

    /// @notice Test whether the word at abs is greater than the word at otherAbs.
    /// @dev Both reads are unchecked and use EVM zero-padding. Caller owns both
    /// logical bounds. Ordering is unsigned over all 256 bits.
    /// @param abs Full-width absolute position of the left operand.
    /// @param otherAbs Full-width absolute position of the right operand.
    /// @return result Comparison result; a failed comparison does not revert.
    function gtAt32(uint abs, uint otherAbs) internal pure returns (bool result) {
        return uint(read32(abs)) > uint(read32(otherAbs));
    }

    /// @notice Test whether the word at abs is less than or equal to the word at otherAbs.
    /// @dev Both reads are unchecked and use EVM zero-padding. Caller owns both
    /// logical bounds. Ordering is unsigned over all 256 bits.
    /// @param abs Full-width absolute position of the left operand.
    /// @param otherAbs Full-width absolute position of the right operand.
    /// @return result Comparison result; a failed comparison does not revert.
    function leAt32(uint abs, uint otherAbs) internal pure returns (bool result) {
        return !gtAt32(abs, otherAbs);
    }

    /// @notice Test whether the word at abs is greater than or equal to the word at otherAbs.
    /// @dev Both reads are unchecked and use EVM zero-padding. Caller owns both
    /// logical bounds. Ordering is unsigned over all 256 bits.
    /// @param abs Full-width absolute position of the left operand.
    /// @param otherAbs Full-width absolute position of the right operand.
    /// @return result Comparison result; a failed comparison does not revert.
    function geAt32(uint abs, uint otherAbs) internal pure returns (bool result) {
        return !ltAt32(abs, otherAbs);
    }

    /// @notice Check an already-validated BALANCE_CONSTRAINTS payload against a balance.
    /// @dev Unchecked absolute calldata reads: the caller must establish that abs points
    /// to the complete 96-byte payload of a validated BALANCE_CONSTRAINTS block,
    /// for example through unpackFixed. abs points after the header, not at it.
    /// Checks asset identity before inclusive full-width minimum/maximum bounds.
    /// Zero maximum is literal. Does not validate header, containment, or provenance.
    /// Reverts UnexpectedValue or OutOfRange on value mismatch.
    /// @param abs Absolute start of the already-validated payload.
    /// @param asset Expected balance asset identifier.
    /// @param amount Full-width balance amount to check against both bounds.
    function checkBalanceConstraints(uint abs, bytes32 asset, uint amount) internal pure {
        unchecked {
            if (!equal32(abs, asset)) revert UnexpectedValue();
            if (either(gt32(abs + 32, amount), lt32(abs + 64, amount))) revert OutOfRange();
        }
    }

    /// @notice Check an already-validated POSITION_CONSTRAINTS payload against a position.
    /// @dev Unchecked absolute calldata reads: the caller must establish that abs points
    /// to the complete 128-byte payload of a validated POSITION_CONSTRAINTS block,
    /// for example through unpackFixed. abs points after the header, not at it.
    /// Checks identifiers before inclusive quantity bounds; zero maximum debt is literal.
    /// Does not validate header, containment, or provenance, modify position, or check
    /// its counterparty. Reverts UnexpectedValue or OutOfRange on value mismatch.
    /// @param abs Absolute start of the already-validated payload.
    /// @param position Position whose identifiers and full-width quantities are checked.
    function checkPositionConstraints(uint abs, Position memory position) internal pure {
        unchecked {
            if (either(!equal32(abs, position.asset), !equal32(abs + 64, position.liability))) revert UnexpectedValue();
            if (either(gt32(abs + 32, position.amount), lt32(abs + 96, position.debt))) revert OutOfRange();
        }
    }

    // Header validation: exact header, key only, or packed specification.

    /// @notice Require a matching key and return the declared payload length.
    /// @dev Does not establish containment or narrow abs. Callers must prove
    /// containment before packing cursors or trusting field loads.
    /// @param abs Absolute header position, possibly not yet proven to fit uint32.
    /// @param key Required block key; mismatch reverts InvalidBlock.
    /// @return len Declared uint32 payload length, widened to uint256.
    function expectKey(uint abs, bytes4 key) private pure returns (uint len) {
        assembly ("memory-safe") {
            let head := calldataload(abs)
            if iszero(eq(shr(224, head), shr(224, key))) {
                mstore(0, INVALID_BLOCK)
                revert(28, 4)
            }
            len := and(shr(192, head), 0xffffffff)
        }
    }

    /// @notice Require a matching key and length range, returning the declared payload length.
    /// @dev Reads one header. Does not check header or payload containment; the caller
    /// must establish it before using the length for trusted reads. Reverts InvalidBlock
    /// on a key or length mismatch. A zero maximum is unbounded.
    /// @param abs Absolute header position; does not establish containment.
    /// @param spec Key in bits 224-255, minimum in 192-223, maximum in 160-191.
    /// @return len Declared uint32 payload length, widened to uint256.
    function expectSpec(uint abs, uint spec) private pure returns (uint len) {
        assembly ("memory-safe") {
            let head := calldataload(abs)
            len := and(shr(192, head), 0xffffffff)
            let maximum := and(shr(160, spec), 0xffffffff)
            if or(
                or(iszero(eq(shr(224, head), shr(224, spec))), lt(len, and(shr(192, spec), 0xffffffff))),
                and(iszero(iszero(maximum)), gt(len, maximum))
            ) {
                mstore(0, INVALID_BLOCK)
                revert(28, 4)
            }
        }
    }

    /// @notice Validate the eight-byte header at an absolute calldata position.
    /// @dev Checks the key and declared payload length together. Reverts InvalidBlock
    /// on mismatch. Does not check containment; calldata reads are zero-padded.
    /// @param abs Absolute header position, not a packed cursor.
    /// @param header Right-aligned eight-byte key/length header; nonzero upper bits fail validation.
    function expectHeader(uint abs, uint header) internal pure {
        assembly ("memory-safe") {
            if iszero(eq(shr(192, calldataload(abs)), header)) {
                mstore(0, INVALID_BLOCK)
                revert(28, 4)
            }
        }
    }

    /// @notice Validate a header against a key and exact payload length.
    /// @dev Requires len <= uint32.max. Delegates to the packed-header check;
    /// does not establish containment.
    /// @param abs Absolute header position.
    /// @param key Required block key.
    /// @param len Required payload length, excluding the eight-byte header.
    function expectHeader(uint abs, bytes4 key, uint len) private pure {
        expectHeader(abs, (uint(uint32(key)) << 32) | len);
    }

    /// @notice Pack a clean cursor from two already validated absolute positions.
    /// @dev Performs no validation or masking. Requires abs <= endAbs <= uint32.max,
    /// proven by containment, exactness, or final-child validation before calling.
    /// @param abs Validated inclusive position, with no cursor metadata or end lane.
    /// @param endAbs Validated exclusive end of the selected range.
    /// @return resultCur Packed position/end cursor with zero metadata.
    function pack(uint abs, uint endAbs) private pure returns (uint resultCur) {
        return Cursors.pack(abs, endAbs);
    }

    /// @notice Validate a final child block and select its payload.
    /// @dev Requires an already bounded endAbs fitting uint32, abs at or after
    /// the parent payload start, and abs + 8 not overflowing uint256.
    /// Checks body <= endAbs before accepting the expected key/length header. This proves
    /// the preceding fixed prefix and child header fit and the child consumes the
    /// parent remainder exactly. Reverts InvalidBlock on any mismatch.
    /// @param abs Absolute child-header position, kept full-width until validation.
    /// @param endAbs Exclusive end of the already validated parent.
    /// @param key Required child key.
    /// @return payloadCur Clean child-payload cursor; its end equals the parent end.
    function tail(uint abs, uint endAbs, bytes4 key) private pure returns (uint payloadCur) {
        assembly ("memory-safe") {
            let body := add(abs, 8)
            let len := sub(endAbs, body)
            if or(lt(endAbs, body), iszero(eq(shr(192, calldataload(abs)), or(shl(32, shr(224, key)), len)))) {
                mstore(0, INVALID_BLOCK)
                revert(28, 4)
            }
            payloadCur := or(body, shl(32, endAbs))
        }
    }

    /// @notice Validate two same-key children occupying a parent's remainder.
    /// @dev Requires a bounded uint32 endAbs, abs at or after the parent payload
    /// start, and abs + 16 + uint32.max not overflowing uint256. The first
    /// child's end stays full-width until tail proves the final child fits.
    /// That proof also bounds the first child and preceding fixed prefix;
    /// no separate intermediate containment check is needed.
    /// @param abs Absolute first-child header position.
    /// @param endAbs Exclusive end of the already validated parent.
    /// @param key Required key for both children.
    /// @return firstCur Clean cursor over the first child's payload.
    /// @return lastCur Clean cursor over the final child's payload, ending at endAbs.
    function pair(uint abs, uint endAbs, bytes4 key) private pure returns (uint firstCur, uint lastCur) {
        uint len = expectKey(abs, key);
        unchecked {
            uint body = abs + 8;
            uint nextAbs = body + len;
            lastCur = tail(nextAbs, endAbs, key);
            firstCur = pack(body, nextAbs);
        }
    }

    /// @notice Count a matching run as a hint between absolute positions.
    /// @dev Unchecked calldata reads; neither malformed data nor reversed ranges revert.
    /// Requires abs and endAbs to fit uint32 so full-width end arithmetic cannot overflow.
    /// @param abs Absolute start of the candidate run.
    /// @param endAbs Exclusive source boundary.
    /// @param key Key forming the consecutive run.
    /// @return total Number of complete matching blocks before the first stopping condition.
    function runCountAt(uint abs, uint endAbs, bytes4 key) private pure returns (uint total) {
        uint expected = uint32(key);
        assembly ("memory-safe") {
            for {} lt(abs, endAbs) {} {
                let head := calldataload(abs)
                if iszero(eq(shr(224, head), expected)) {
                    break
                }
                let nextAbs := add(add(abs, 8), and(shr(192, head), 0xffffffff))
                if gt(nextAbs, endAbs) {
                    break
                }
                abs := nextAbs
                total := add(total, 1)
            }
        }
    }

    // -------------------------------------------------------------------------
    // Packed-cursor primitives: cur / ...Cur
    // -------------------------------------------------------------------------

    /// @notice Return the number of bytes remaining in the cursor.
    /// @dev Requires current <= end; performs no bounds or provenance checks.
    /// Ignores metadata and does not advance the cursor or skip a block header.
    /// @param cur Validated source cursor.
    /// @return size Remaining byte count.
    function length(uint cur) internal pure returns (uint size) {
        return Cursors.length(cur);
    }

    /// @notice Advance a cursor by exactly size bytes after checking containment.
    /// @dev Requires size <= uint32.max + 8. This precondition prevents overflow
    /// in the full-width position addition; arbitrary uint256 sizes are unsupported.
    /// Rejects reversed ranges and advances beyond the source end with OutOfBounds.
    /// Preserves the end and metadata. Does not validate headers or calldata provenance.
    /// @param cur Bounded source cursor.
    /// @param size Total bytes to advance, including any header required by the caller.
    /// @return nextCur Advanced source cursor with the original end and metadata.
    function advance(uint cur, uint size) internal pure returns (uint nextCur) {
        unchecked {
            if (uint(uint32(cur)) + size > uint32(cur >> 32)) revert OutOfBounds();
            // Containment proves no carry into the end lane.
            nextCur = cur + size;
        }
    }

    /// @notice Validate containment and select the payload after a fixed prefix.
    /// @dev Requires a schema-validated uint32 length. Checks block containment once,
    /// then rejects amount > len with InvalidBlock. The payloadCur proves the skipped
    /// prefix fits, allowing trusted fixed-field loads without another bounds check.
    /// @param cur Bounded source cursor positioned at the block header.
    /// @param len Validated payload length, excluding the header.
    /// @param amount Payload bytes to skip; may equal len to produce an empty range.
    /// @return abs Original payload start, before the validated prefix.
    /// @return payloadCur Clean cursor covering the payload remainder through the block end.
    /// @return nextCur Advanced source cursor preserving its original end and metadata.
    function payload(uint cur, uint len, uint amount) private pure returns (uint abs, uint payloadCur, uint nextCur) {
        unchecked {
            nextCur = advance(cur, 8 + len);
        }
        if (amount > len) revert InvalidBlock();
        unchecked {
            abs = uint(uint32(cur)) + 8;
            payloadCur = pack(abs + amount, uint32(nextCur));
        }
    }

    // -------------------------------------------------------------------------
    // Cursor hashing and conversions
    // -------------------------------------------------------------------------

    /// @notice Compute keccak256 over the cursor's remaining calldata range.
    /// @dev Requires current <= end <= calldatasize; performs no repeated bounds
    /// or header checks. Ignores metadata and does not advance the cursor. Copies
    /// to temporary free memory because KECCAK256 reads memory, but does not
    /// allocate a bytes value or advance the free-memory pointer. No header is skipped.
    /// @param cur Validated calldata cursor over exactly the bytes to hash.
    /// @return digest Keccak-256 digest of the selected range.
    function hash(uint cur) internal pure returns (bytes32 digest) {
        return Cursors.hash(cur);
    }

    /// @notice Expose the cursor's remaining range as bytes in calldata.
    /// @dev Requires a validated range: current <= end <= calldatasize.
    /// Performs no header, bounds, or provenance checks. Ignores metadata and
    /// neither advances the cursor nor copies or allocates memory. Does not skip a header.
    /// @param cur Validated calldata cursor; use a payload cursor to exclude its header.
    /// @return data Calldata view of the remaining range.
    function toBytes(uint cur) internal pure returns (bytes calldata data) {
        return Cursors.toBytes(cur);
    }

    /// @notice Validate the cursor's bounds and expose its remaining calldata range.
    /// @dev Requires current <= end <= calldatasize; otherwise reverts OutOfBounds.
    /// A zero cursor returns msg.data[0:0]. Ignores metadata and performs no block
    /// or schema validation. Neither advances the cursor nor copies or allocates memory.
    function toBytesChecked(uint cur) internal pure returns (bytes calldata data) {
        return Cursors.toBytesChecked(cur);
    }

    /// @notice Expose the cursor's remaining range as a string in calldata.
    /// @dev Shares toBytes's validated-range requirement and performs no UTF-8
    /// validation. Neither advances the cursor nor copies or allocates memory.
    /// Assignment to string memory copies only when the caller requests it.
    /// @param cur Validated calldata cursor over the desired string bytes.
    /// @return data Calldata string view of the remaining range.
    function toString(uint cur) internal pure returns (string calldata data) {
        return Cursors.toString(cur);
    }

    /// @notice Validate cursor bounds and expose the remaining range as a calldata string.
    /// @dev Shares toBytesChecked's bounds checks and OutOfBounds error.
    /// Performs no UTF-8, block, or schema validation. Ignores metadata;
    /// neither advances the cursor nor copies or allocates memory.
    function toStringChecked(uint cur) internal pure returns (string calldata data) {
        return Cursors.toStringChecked(cur);
    }

    // -------------------------------------------------------------------------
    // Whole-stream validation
    // -------------------------------------------------------------------------

    /// @notice Validate the entire remaining stream as zero or more blocks with key.
    /// @dev Checks complete headers before reading them, then keys and payload bounds.
    /// Empty ranges pass. Reverts OutOfBounds for reversed or truncated ranges and
    /// InvalidBlock for key mismatches. Does not advance or inspect payload contents.
    /// Callers establish calldata provenance; cursor metadata is ignored.
    function expectRun(uint cur, bytes4 key) internal pure {
        uint abs = uint32(cur);
        uint end = uint32(cur >> 32);
        if (abs > end) revert OutOfBounds();
        while (abs < end) {
            unchecked {
                if (end - abs < 8) revert OutOfBounds();
                uint size = 8 + expectKey(abs, key);
                if (size > end - abs) revert OutOfBounds();
                abs += size;
            }
        }
    }

    /// @notice Validate the entire remaining stream as zero or more fixed-size blocks.
    /// @dev Checks each block's containment before its complete header, in stream order.
    /// Reverts OutOfBounds for reversed ranges or incomplete blocks, and InvalidBlock
    /// for header mismatches. Empty ranges pass. Does not read payloads, advance the
    /// caller's cursor, or validate calldata provenance. Cursor metadata is ignored.
    /// @param cur Bounded source cursor over the complete stream to validate.
    /// @param header Right-aligned key/length header; callers supply zero upper bits.
    function expectRunFixed(uint cur, uint header) internal pure {
        uint abs = uint32(cur);
        uint endAbs = uint32(cur >> 32);
        uint size = 8 + uint(uint32(header));
        if (abs > endAbs) revert OutOfBounds();
        while (abs < endAbs) {
            unchecked {
                if (endAbs - abs < size) revert OutOfBounds();
                expectHeader(abs, header);
                abs += size;
            }
        }
    }

    // -------------------------------------------------------------------------
    // Cursor scan hints
    // -------------------------------------------------------------------------

    /// @notice Estimate the number of consecutive complete blocks with key.
    /// @dev Hint only: does not validate schemas or malformed/trailing data. Stops
    /// before a different key or a declared block that exceeds the source end.
    /// Empty or reversed ranges return zero. Normal decoding must still validate
    /// the input; callers establish calldata provenance. Metadata is ignored.
    /// @param cur Source cursor positioned at the first candidate block header.
    /// @param key Key forming the consecutive run.
    /// @return total Number of complete matching blocks within the supplied boundary.
    function runCount(uint cur, bytes4 key) internal pure returns (uint total) {
        return runCountAt(uint32(cur), uint32(cur >> 32), key);
    }

    // -------------------------------------------------------------------------
    // Cursor selection helpers: enter, take, unpack
    // -------------------------------------------------------------------------

    /// @notice Enter a matching payload after skipping a fixed prefix.
    /// @dev Checks schema, containment, then prefix length, in that order.
    /// A prefix longer than the payload reverts InvalidBlock.
    /// @param cur Bounded source cursor positioned at the block header.
    /// @param spec Packed key/minimum/maximum specification, as accepted by take.
    /// @param amount Number of payload bytes to skip, excluding the block header.
    /// @return abs Original payload start; reads within the validated amount-byte prefix are in bounds.
    /// @return payloadCur Clean cursor after the prefix; skipping the entire payload is valid.
    /// @return nextCur Advanced source cursor preserving its original end and metadata.
    function enter(uint cur, uint spec, uint amount) internal pure returns (uint abs, uint payloadCur, uint nextCur) {
        return payload(cur, expectSpec(uint32(cur), spec), amount);
    }

    /// @notice Enter a keyed payload after skipping a fixed prefix.
    /// @dev Checks key, containment, then prefix length, in that order.
    /// A prefix longer than the payload reverts InvalidBlock.
    /// @param cur Bounded source cursor positioned at the block header.
    /// @param key Required block key.
    /// @param amount Number of payload bytes to skip, excluding the block header.
    /// @return abs Original payload start; reads within the validated amount-byte prefix are in bounds.
    /// @return payloadCur Clean cursor after the prefix; skipping the entire payload is valid.
    /// @return nextCur Advanced source cursor preserving its original end and metadata.
    function enter(uint cur, bytes4 key, uint amount) internal pure returns (uint abs, uint payloadCur, uint nextCur) {
        return payload(cur, expectKey(uint32(cur), key), amount);
    }

    /// @notice Enter an exact-header block after validating a fixed prefix.
    /// @dev Checks the header, containment, then prefix length, once each in that order.
    /// Does not interpret the prefix or remaining payload; an empty remainder is valid.
    /// @param cur Bounded source cursor positioned at the block header.
    /// @param header Right-aligned key/length header; nonzero upper bits fail validation.
    /// @param amount Payload bytes to skip after proving they fit.
    /// @return abs Original payload start, before the validated prefix.
    /// @return payloadCur Clean cursor over the remaining payload after the prefix.
    /// @return nextCur Advanced source cursor preserving its original end and metadata.
    function enterFixed(
        uint cur,
        uint header,
        uint amount
    ) internal pure returns (uint abs, uint payloadCur, uint nextCur) {
        expectHeader(uint32(cur), header);
        return payload(cur, uint32(header), amount);
    }

    /// @notice Enter a matching block occupying the entire range and skip a fixed prefix.
    /// @dev Reuses unpackExact validation, then checks only the prefix length.
    /// Schema mismatch, truncation, trailing bytes, and oversized prefixes revert InvalidBlock.
    /// @param cur Source cursor covering exactly one block, including its header.
    /// @param spec Packed key/minimum/maximum specification, as accepted by take.
    /// @param amount Payload bytes to skip; may equal the full payload length.
    /// @return abs Original payload start; the amount-byte prefix is safe to read.
    /// @return payloadCur Clean cursor over the remaining payload; no source remainder is returned.
    function enterExact(uint cur, uint spec, uint amount) internal pure returns (uint abs, uint payloadCur) {
        payloadCur = unpackExact(cur, spec);
        abs = uint32(payloadCur);
        if (amount > length(payloadCur)) revert InvalidBlock();
        unchecked { payloadCur += amount; }
    }

    /// @notice Select the complete next block, including its eight-byte header.
    /// @dev Checks header and payload containment; does not constrain the key or payload shape.
    /// Reverts OutOfBounds if the declared block exceeds the cursor end.
    /// @param cur Bounded source cursor positioned at the block header.
    /// @return blockCur Clean cursor covering the header and payload; trailing source bytes are excluded.
    /// @return nextCur Advanced source cursor preserving its original end and metadata.
    function take(uint cur) internal pure returns (uint blockCur, uint nextCur) {
        uint len;
        assembly ("memory-safe") {
            len := and(shr(192, calldataload(and(cur, 0xffffffff))), 0xffffffff)
        }
        unchecked {
            nextCur = advance(cur, 8 + len);
            blockCur = pack(uint32(cur), uint32(nextCur));
        }
    }

    /// @notice Select a complete block matching a packed specification.
    /// @dev Checks key and payload length before containment. A zero maximum is unbounded.
    /// Reverts InvalidBlock on schema mismatch or OutOfBounds on failed containment.
    /// @param cur Bounded source cursor positioned at the block header.
    /// @param spec Packed specification: key in bits 224-255, minimum in 192-223,
    /// maximum in 160-191. Other lanes are ignored.
    /// @return blockCur Clean cursor covering the matching block's header and payload.
    /// @return nextCur Advanced source cursor preserving its original end and metadata.
    function take(uint cur, uint spec) internal pure returns (uint blockCur, uint nextCur) {
        uint abs = uint32(cur);
        unchecked {
            nextCur = advance(cur, 8 + expectSpec(abs, spec));
            blockCur = pack(abs, uint32(nextCur));
        }
    }

    /// @notice Select a complete block with the required key.
    /// @dev Checks the key before containment; imposes no payload length constraint.
    /// Reverts InvalidBlock on key mismatch or OutOfBounds on failed containment.
    /// @param cur Bounded source cursor positioned at the block header.
    /// @param key Required block key.
    /// @return blockCur Clean cursor covering the matching block's header and payload.
    /// @return nextCur Advanced source cursor preserving its original end and metadata.
    function take(uint cur, bytes4 key) internal pure returns (uint blockCur, uint nextCur) {
        uint abs = uint32(cur);
        unchecked {
            nextCur = advance(cur, 8 + expectKey(abs, key));
            blockCur = pack(abs, uint32(nextCur));
        }
    }

    /// @notice Select a block with an exact key and payload length.
    /// @dev Validates the full header once, then checks containment.
    /// Reverts InvalidBlock on header mismatch or OutOfBounds on failed containment.
    /// @param cur Bounded source cursor positioned at the block header.
    /// @param header Right-aligned header: key in bits 32-63, payload length in bits 0-31.
    /// @return blockCur Clean cursor covering the exact header and its payload.
    /// @return nextCur Advanced source cursor preserving its original end and metadata.
    function takeFixed(uint cur, uint header) internal pure returns (uint blockCur, uint nextCur) {
        uint abs = uint32(cur);
        expectHeader(abs, header);
        unchecked {
            nextCur = advance(cur, 8 + uint(uint32(header)));
            blockCur = pack(abs, uint32(nextCur));
        }
    }

    /// @notice Select a matching block occupying the entire supplied range.
    /// @dev End equality proves containment without a separate bounds check.
    /// Schema mismatch, truncation, and trailing bytes all revert InvalidBlock.
    /// @param cur Source cursor covering exactly one expected block, including its header.
    /// @param spec Packed key/minimum/maximum specification, as accepted by take.
    /// @return blockCur Clean cursor including the header; no source remainder is returned.
    function takeExact(uint cur, uint spec) internal pure returns (uint blockCur) {
        uint abs = uint32(cur);
        uint endAbs;
        unchecked {
            // Both position and declared length fit uint32; keep the sum full-width.
            endAbs = abs + 8 + expectSpec(abs, spec);
        }
        if (endAbs != uint32(cur >> 32)) revert InvalidBlock();
        blockCur = pack(abs, endAbs);
    }

    /// @notice Select an exact-header block occupying the entire supplied range.
    /// @dev Checks the full header, then end equality, without a separate containment check.
    /// Header mismatch, truncation, and trailing bytes all revert InvalidBlock.
    /// Calldata provenance remains the caller's responsibility.
    /// @param cur Source cursor covering exactly one block, including its header.
    /// @param header Right-aligned key/length header; nonzero upper bits fail validation.
    /// @return blockCur Clean cursor including the header; no source remainder is returned.
    function takeFixedExact(uint cur, uint header) internal pure returns (uint blockCur) {
        uint abs = uint32(cur);
        expectHeader(abs, header);
        uint endAbs;
        unchecked {
            // Keep the sum full-width so a large length cannot wrap into the end lane.
            endAbs = abs + 8 + uint(uint32(header));
        }
        if (endAbs != uint32(cur >> 32)) revert InvalidBlock();
        blockCur = pack(abs, endAbs);
    }

    /// @notice Select a keyed block's payload and advance the source cursor.
    /// @dev Checks the key before complete containment, once each. Does not validate
    /// payload contents. Empty payloads are valid; calldata provenance is caller-owned.
    /// @param cur Bounded source cursor positioned at the block header.
    /// @param key Required block key.
    /// @return payloadCur Clean cursor over the payload, excluding its header.
    /// @return nextCur Advanced source cursor preserving its original end and metadata.
    function unpack(uint cur, bytes4 key) internal pure returns (uint payloadCur, uint nextCur) {
        uint abs = uint32(cur);
        unchecked {
            nextCur = advance(cur, 8 + expectKey(abs, key));
            payloadCur = pack(abs + 8, uint32(nextCur));
        }
    }

    /// @notice Select a specification-matching payload and advance the source cursor.
    /// @dev Checks key and payload length before complete containment, once each.
    /// A zero maximum is unbounded. Does not validate payload contents or calldata provenance.
    /// @param cur Bounded source cursor positioned at the block header.
    /// @param spec Packed key/minimum/maximum specification, as accepted by take.
    /// @return payloadCur Clean cursor over the payload, excluding its header.
    /// @return nextCur Advanced source cursor preserving its original end and metadata.
    function unpack(uint cur, uint spec) internal pure returns (uint payloadCur, uint nextCur) {
        uint abs = uint32(cur);
        unchecked {
            nextCur = advance(cur, 8 + expectSpec(abs, spec));
            payloadCur = pack(abs + 8, uint32(nextCur));
        }
    }

    /// @notice Select an exact-header block's payload and advance the source cursor.
    /// @dev Reuses takeFixed's header and containment checks without repeating them.
    /// The validated header fits, so skipping it cannot carry into the end lane.
    /// Does not validate payload contents; empty payloads are valid.
    /// @param cur Bounded source cursor positioned at the block header.
    /// @param header Right-aligned key/length header; nonzero upper bits fail validation.
    /// @return payloadCur Clean cursor over the payload, excluding its header.
    /// @return nextCur Advanced source cursor preserving its original end and metadata.
    function unpackFixed(uint cur, uint header) internal pure returns (uint payloadCur, uint nextCur) {
        (payloadCur, nextCur) = takeFixed(cur, header);
        unchecked {
            payloadCur += 8;
        }
    }

    /// @notice Select the payload of a matching block occupying the entire range.
    /// @dev Reuses takeExact's schema and end-equality checks. Skipping the validated
    /// header cannot carry into the end lane. Does not inspect payload contents.
    /// Schema mismatch, truncation, and trailing bytes all revert InvalidBlock.
    /// @param cur Source cursor covering exactly one block, including its header.
    /// @param spec Packed key/minimum/maximum specification, as accepted by take.
    /// @return payloadCur Clean payload cursor excluding the header; no remainder is returned.
    function unpackExact(uint cur, uint spec) internal pure returns (uint payloadCur) {
        unchecked { payloadCur = takeExact(cur, spec) + 8; }
    }

    /// @notice Select the payload of an exact-header block occupying the entire range.
    /// @dev Reuses takeFixedExact's header and end-equality checks. The validated header
    /// fits, so skipping it cannot carry into the end lane. Does not inspect payload contents.
    /// Header mismatch, truncation, and trailing bytes all revert InvalidBlock.
    /// @param cur Source cursor covering exactly one block, including its header.
    /// @param header Right-aligned key/length header; nonzero upper bits fail validation.
    /// @return payloadCur Clean payload cursor excluding the header; no remainder is returned.
    function unpackFixedExact(uint cur, uint header) internal pure returns (uint payloadCur) {
        unchecked { payloadCur = takeFixedExact(cur, header) + 8; }
    }

    // Named payload wrappers: delegate validation and advancement to unpack.

    /// @notice Select BYTES's payload and return the advanced source cursor.
    /// @dev Delegates key and containment checks to unpack; empty payloads are valid.
    /// @param cur Bounded source cursor positioned at the BYTES header.
    /// @return payloadCur Clean cursor over the bytes payload, excluding its header.
    /// @return nextCur Advanced source cursor preserving its original end and metadata.
    function unpackBytes(uint cur) internal pure returns (uint payloadCur, uint nextCur) {
        return unpack(cur, Keys.Bytes);
    }

    /// @notice Select STRING's payload and return the advanced source cursor.
    /// @dev Delegates key and containment checks to unpack. Empty strings are valid;
    /// does not validate text encoding or interpret the payload.
    /// @param cur Bounded source cursor positioned at the STRING header.
    /// @return payloadCur Clean cursor over the string bytes, excluding its header.
    /// @return nextCur Advanced source cursor preserving its original end and metadata.
    function unpackString(uint cur) internal pure returns (uint payloadCur, uint nextCur) {
        return unpack(cur, Keys.String);
    }

    /// @notice Select LIST's contents and return the advanced source cursor.
    /// @dev Validates the LIST key and complete containment once. Does not validate
    /// individual items; an empty list is valid. Header mismatch reverts InvalidBlock
    /// before containment failures revert OutOfBounds.
    /// @param cur Bounded source cursor positioned at the LIST header.
    /// @return itemsCur Clean cursor over the list payload, excluding its header.
    /// @return nextCur Advanced source cursor preserving its original end and metadata.
    function unpackList(uint cur) internal pure returns (uint itemsCur, uint nextCur) {
        return unpack(cur, Keys.List);
    }

    /// @notice Decode exactly 32 payload bytes as full-width words.
    /// @dev Checks the key/length header and containment once before trusted reads.
    /// @param cur Bounded source cursor positioned at the block header.
    /// @param key Required block key.
    /// @return a Decoded payload value.
    /// @return nextCur Advanced source preserving its end and metadata.
    function unpack32(uint cur, bytes4 key) internal pure returns (bytes32 a, uint nextCur) {
        uint abs = uint32(cur);
        expectHeader(abs, key, 32);
        nextCur = advance(cur, 40);
        unchecked {
            a = read32(abs + 8);
        }
    }

    /// @notice Decode a block containing exactly two 32-byte words.
    /// @dev Checks the exact key/64-byte header and containment once, then loads
    /// both fields without additional bounds checks. Does not interpret field values.
    /// @param cur Bounded source cursor positioned at the block header.
    /// @param key Required block key.
    /// @return a First payload word.
    /// @return b Second payload word.
    /// @return nextCur Advanced source cursor preserving its original end and metadata.
    function unpack64(uint cur, bytes4 key) internal pure returns (bytes32 a, bytes32 b, uint nextCur) {
        uint abs = uint32(cur);
        expectHeader(abs, key, 64);
        nextCur = advance(cur, 8 + 64);
        assembly ("memory-safe") {
            a := calldataload(add(abs, 8))
            b := calldataload(add(abs, 40))
        }
    }

    /// @notice Decode exactly 96 payload bytes as full-width words.
    /// @dev Checks the key/length header and containment once before trusted reads.
    /// @param cur Bounded source cursor positioned at the block header.
    /// @param key Required block key.
    /// @return a Decoded payload value.
    /// @return b Decoded payload value.
    /// @return c Decoded payload value.
    /// @return nextCur Advanced source preserving its end and metadata.
    function unpack96(uint cur, bytes4 key) internal pure returns (bytes32 a, bytes32 b, bytes32 c, uint nextCur) {
        uint abs = uint32(cur);
        expectHeader(abs, key, 96);
        nextCur = advance(cur, 104);
        unchecked {
            a = read32(abs + 8);
            b = read32(abs + 40);
            c = read32(abs + 72);
        }
    }

    /// @notice Decode exactly 128 payload bytes as full-width words.
    /// @dev Checks the key/length header and containment once before trusted reads.
    /// @param cur Bounded source cursor positioned at the block header.
    /// @param key Required block key.
    /// @return a Decoded payload value.
    /// @return b Decoded payload value.
    /// @return c Decoded payload value.
    /// @return d Decoded payload value.
    /// @return nextCur Advanced source preserving its end and metadata.
    function unpack128(uint cur, bytes4 key) internal pure returns (bytes32 a, bytes32 b, bytes32 c, bytes32 d, uint nextCur) {
        uint abs = uint32(cur);
        expectHeader(abs, key, 128);
        nextCur = advance(cur, 136);
        unchecked {
            a = read32(abs + 8);
            b = read32(abs + 40);
            c = read32(abs + 72);
            d = read32(abs + 104);
        }
    }

    /// @notice Decode a block containing exactly five 32-byte words.
    /// @dev Validates the exact header and containment once before trusted loads.
    /// @param cur Bounded source cursor positioned at the block header.
    /// @param key Required block key.
    /// @return a First payload word.
    /// @return b Second payload word.
    /// @return c Third payload word.
    /// @return d Fourth payload word.
    /// @return e Fifth payload word.
    /// @return nextCur Advanced source cursor preserving its original end and metadata.
    function unpack160(
        uint cur,
        bytes4 key
    ) internal pure returns (bytes32 a, bytes32 b, bytes32 c, bytes32 d, bytes32 e, uint nextCur) {
        uint abs = uint32(cur);
        expectHeader(abs, key, 160);
        nextCur = advance(cur, 8 + 160);
        assembly ("memory-safe") {
            a := calldataload(add(abs, 8))
            b := calldataload(add(abs, 40))
            c := calldataload(add(abs, 72))
            d := calldataload(add(abs, 104))
            e := calldataload(add(abs, 136))
        }
    }

    // Named fixed blocks, ordered by payload size.

    /// @notice Decode ACCOUNT and return the advanced source cursor.
    /// @dev Reuses the fixed-word decoder's exact header and containment checks.
    /// @param cur Bounded source cursor at the block header.
    /// @return account Decoded payload value.
    /// @return nextCur Advanced source preserving its end and metadata.
    function unpackAccount(uint cur) internal pure returns (bytes32 account, uint nextCur) {
        (account, nextCur) = unpack32(cur, Keys.Account);
    }

    /// @notice Decode ASSET and return the advanced source cursor.
    /// @dev Reuses the fixed-word decoder's exact header and containment checks.
    /// @param cur Bounded source cursor at the block header.
    /// @return asset Decoded payload value.
    /// @return nextCur Advanced source preserving its end and metadata.
    function unpackAsset(uint cur) internal pure returns (bytes32 asset, uint nextCur) {
        (asset, nextCur) = unpack32(cur, Keys.Asset);
    }

    /// @notice Decode NODE and return the advanced source cursor.
    /// @dev Reuses the fixed-word decoder's exact header and containment checks.
    /// @param cur Bounded source cursor at the block header.
    /// @return node Decoded payload value.
    /// @return nextCur Advanced source preserving its end and metadata.
    function unpackNode(uint cur) internal pure returns (uint node, uint nextCur) {
        bytes32 a;
        (a, nextCur) = unpack32(cur, Keys.Node);
        node = uint(a);
    }

    /// @notice Decode ENTITY and return the advanced source cursor.
    /// @dev Reuses the fixed-word decoder's exact header and containment checks.
    /// @param cur Bounded source cursor at the block header.
    /// @return entity Decoded payload value.
    /// @return nextCur Advanced source preserving its end and metadata.
    function unpackEntity(uint cur) internal pure returns (uint entity, uint nextCur) {
        bytes32 a;
        (a, nextCur) = unpack32(cur, Keys.Entity);
        entity = uint(a);
    }

    /// @notice Decode STATUS and return the advanced source cursor.
    /// @dev Validates the exact header and containment through unpack32.
    /// @param cur Bounded source cursor at the block header.
    /// @return code Full-width status value.
    /// @return nextCur Advanced source preserving its end and metadata.
    function unpackStatus(uint cur) internal pure returns (uint code, uint nextCur) {
        bytes32 a;
        (a, nextCur) = unpack32(cur, Keys.Status);
        code = uint(a);
    }

    /// @notice Consume one CODES block containing packed identifiers.
    /// @dev Validates the exact header and containment through unpack32, not code semantics.
    /// @param cur Bounded source cursor at the block header.
    /// @return codes Full-width packed identifiers.
    /// @return nextCur Advanced source cursor preserving its end.
    function unpackCodes(uint cur) internal pure returns (uint codes, uint nextCur) {
        bytes32 a;
        (a, nextCur) = unpack32(cur, Keys.Codes);
        codes = uint(a);
    }

    /// @notice Decode LIMITS and return the advanced source cursor.
    /// @dev Reuses the fixed-word decoder's exact header and containment checks.
    /// @param cur Bounded source cursor at the block header.
    /// @return limits Decoded payload value.
    /// @return nextCur Advanced source preserving its end and metadata.
    function unpackLimits(uint cur) internal pure returns (uint limits, uint nextCur) {
        bytes32 a;
        (a, nextCur) = unpack32(cur, Keys.Limits);
        limits = uint(a);
    }

    /// @notice Decode AMOUNT and return the advanced source cursor.
    /// @dev Reuses the fixed-word decoder's exact header and containment checks.
    /// @param cur Bounded source cursor at the block header.
    /// @return asset Decoded payload value.
    /// @return amount Decoded payload value.
    /// @return nextCur Advanced source preserving its end and metadata.
    function unpackAmount(uint cur) internal pure returns (bytes32 asset, uint amount, uint nextCur) {
        bytes32 a;
        (asset, a, nextCur) = unpack64(cur, Keys.Amount);
        amount = uint(a);
    }

    /// @notice Decode BALANCE and return the advanced source cursor.
    /// @dev Reuses the fixed-word decoder's exact header and containment checks.
    /// The source boundary and all metadata are preserved; only position changes.
    /// @param cur Bounded source cursor positioned at the BALANCE header.
    /// @return asset Encoded asset identifier.
    /// @return amount Unsigned balance amount.
    /// @return nextCur Source cursor positioned immediately after this block.
    function unpackBalance(uint cur) internal pure returns (bytes32 asset, uint amount, uint nextCur) {
        bytes32 a;
        (asset, a, nextCur) = unpack64(cur, Keys.Balance);
        amount = uint(a);
    }

    /// @notice Decode ASSETLIABILITY and return the advanced source cursor.
    /// @dev Reuses the fixed-word decoder's exact header and containment checks.
    /// @param cur Bounded source cursor at the block header.
    /// @return asset Decoded payload value.
    /// @return liability Decoded payload value.
    /// @return nextCur Advanced source preserving its end and metadata.
    function unpackAssetLiability(uint cur) internal pure returns (bytes32 asset, bytes32 liability, uint nextCur) {
        (asset, liability, nextCur) = unpack64(cur, Keys.AssetLiability);
    }

    /// @notice Decode ACCOUNTASSET and return the advanced source cursor.
    /// @dev Reuses the fixed-word decoder's exact header and containment checks.
    /// @param cur Bounded source cursor at the block header.
    /// @return account Decoded payload value.
    /// @return asset Decoded payload value.
    /// @return nextCur Advanced source preserving its end and metadata.
    function unpackAccountAsset(uint cur) internal pure returns (bytes32 account, bytes32 asset, uint nextCur) {
        (account, asset, nextCur) = unpack64(cur, Keys.AccountAsset);
    }

    /// @notice Decode HOSTASSET and return the advanced source cursor.
    /// @dev Reuses the fixed-word decoder's exact header and containment checks.
    /// @param cur Bounded source cursor at the block header.
    /// @return host Decoded payload value.
    /// @return asset Decoded payload value.
    /// @return nextCur Advanced source preserving its end and metadata.
    function unpackHostAsset(uint cur) internal pure returns (uint host, bytes32 asset, uint nextCur) {
        bytes32 a;
        (a, asset, nextCur) = unpack64(cur, Keys.HostAsset);
        host = uint(a);
    }

    /// @notice Decode BOOTSTRAP and return the advanced source cursor.
    /// @dev Reuses the fixed-word decoder's exact header and containment checks.
    /// @param cur Bounded source cursor at the block header.
    /// @return asset Decoded payload value.
    /// @return amount Decoded payload value.
    /// @return budget Decoded payload value.
    /// @return nextCur Advanced source preserving its end and metadata.
    function unpackBootstrap(uint cur) internal pure returns (bytes32 asset, uint amount, uint budget, uint nextCur) {
        bytes32 a;
        bytes32 b;
        (asset, a, b, nextCur) = unpack96(cur, Keys.Bootstrap);
        amount = uint(a);
        budget = uint(b);
    }

    /// @notice Decode ALLOCATION and return the advanced source cursor.
    /// @dev Reuses the fixed-word decoder's exact header and containment checks.
    /// @param cur Bounded source cursor at the block header.
    /// @return host Decoded payload value.
    /// @return asset Decoded payload value.
    /// @return amount Decoded payload value.
    /// @return nextCur Advanced source preserving its end and metadata.
    function unpackAllocation(uint cur) internal pure returns (uint host, bytes32 asset, uint amount, uint nextCur) {
        bytes32 a;
        bytes32 b;
        (a, asset, b, nextCur) = unpack96(cur, Keys.Allocation);
        host = uint(a);
        amount = uint(b);
    }

    /// @notice Decode ALLOWANCE and return the advanced source cursor.
    /// @dev Reuses the fixed-word decoder's exact header and containment checks.
    /// @param cur Bounded source cursor at the block header.
    /// @return host Decoded payload value.
    /// @return asset Decoded payload value.
    /// @return amount Decoded payload value.
    /// @return nextCur Advanced source preserving its end and metadata.
    function unpackAllowance(uint cur) internal pure returns (uint host, bytes32 asset, uint amount, uint nextCur) {
        bytes32 a;
        bytes32 b;
        (a, asset, b, nextCur) = unpack96(cur, Keys.Allowance);
        host = uint(a);
        amount = uint(b);
    }

    /// @notice Decode CUSTODY and return the advanced source cursor.
    /// @dev Reuses the fixed-word decoder's exact header and containment checks.
    /// @param cur Bounded source cursor at the block header.
    /// @return host Decoded payload value.
    /// @return asset Decoded payload value.
    /// @return amount Decoded payload value.
    /// @return nextCur Advanced source preserving its end and metadata.
    function unpackCustody(uint cur) internal pure returns (uint host, bytes32 asset, uint amount, uint nextCur) {
        bytes32 a;
        bytes32 b;
        (a, asset, b, nextCur) = unpack96(cur, Keys.Custody);
        host = uint(a);
        amount = uint(b);
    }

    /// @notice Decode ACCOUNTAMOUNT and return the advanced source cursor.
    /// @dev Reuses the fixed-word decoder's exact header and containment checks.
    /// @param cur Bounded source cursor at the block header.
    /// @return account Decoded payload value.
    /// @return asset Decoded payload value.
    /// @return amount Decoded payload value.
    /// @return nextCur Advanced source preserving its end and metadata.
    function unpackAccountAmount(uint cur) internal pure returns (bytes32 account, bytes32 asset, uint amount, uint nextCur) {
        bytes32 a;
        (account, asset, a, nextCur) = unpack96(cur, Keys.AccountAmount);
        amount = uint(a);
    }

    /// @notice Decode HOST_AMOUNT and return the advanced source cursor.
    /// @dev Validates the exact header and containment through unpack96.
    /// @param cur Bounded source cursor at the block header.
    /// @return host Full-width host value.
    /// @return asset Encoded asset identifier.
    /// @return amount Full-width amount.
    /// @return nextCur Advanced source preserving its end and metadata.
    function unpackHostAmount(uint cur) internal pure returns (uint host, bytes32 asset, uint amount, uint nextCur) {
        bytes32 a;
        bytes32 b;
        (a, asset, b, nextCur) = unpack96(cur, Keys.HostAmount);
        host = uint(a);
        amount = uint(b);
    }

    /// @notice Decode HOSTACCOUNTASSET and return the advanced source cursor.
    /// @dev Reuses the fixed-word decoder's exact header and containment checks.
    /// @param cur Bounded source cursor at the block header.
    /// @return host Decoded payload value.
    /// @return account Decoded payload value.
    /// @return asset Decoded payload value.
    /// @return nextCur Advanced source preserving its end and metadata.
    function unpackHostAccountAsset(uint cur) internal pure returns (uint host, bytes32 account, bytes32 asset, uint nextCur) {
        bytes32 a;
        (a, account, asset, nextCur) = unpack96(cur, Keys.HostAccountAsset);
        host = uint(a);
    }

    /// @notice Decode BALANCECONSTRAINTS without enforcing its quantity constraints.
    /// @dev Validates header and containment once, then copies the full-width fields into the struct.
    function unpackBalanceConstraints(uint cur) internal pure returns (BalanceConstraints memory value, uint nextCur) {
        uint abs = uint32(cur);
        expectHeader(abs, Headers.BalanceConstraints);
        nextCur = advance(cur, 8 + 96);
        assembly ("memory-safe") {
            calldatacopy(value, add(abs, 8), 96)
        }
    }

    /// @notice Decode QUOTE and return the advanced source cursor.
    /// @dev Reuses the fixed-word decoder's exact header and containment checks.
    /// @param cur Bounded source cursor at the block header.
    /// @return asset Decoded payload value.
    /// @return amount Decoded payload value.
    /// @return liability Decoded payload value.
    /// @return debt Decoded payload value.
    /// @return nextCur Advanced source preserving its end and metadata.
    function unpackQuote(uint cur) internal pure returns (bytes32 asset, uint amount, bytes32 liability, uint debt, uint nextCur) {
        bytes32 a;
        bytes32 b;
        (asset, a, liability, b, nextCur) = unpack128(cur, Keys.Quote);
        amount = uint(a);
        debt = uint(b);
    }

    /// @notice Decode TRANSACTION and return the advanced source cursor.
    /// @dev Reuses the fixed-word decoder's exact header and containment checks.
    /// @param cur Bounded source cursor at the block header.
    /// @return from Decoded payload value.
    /// @return to Decoded payload value.
    /// @return asset Decoded payload value.
    /// @return amount Decoded payload value.
    /// @return nextCur Advanced source preserving its end and metadata.
    function unpackTransaction(uint cur) internal pure returns (bytes32 from, bytes32 to, bytes32 asset, uint amount, uint nextCur) {
        bytes32 a;
        (from, to, asset, a, nextCur) = unpack128(cur, Keys.Transaction);
        amount = uint(a);
    }

    /// @notice Decode HOST_ACCOUNT_AMOUNT and return the advanced source cursor.
    /// @dev Validates the exact header and containment through unpack128.
    /// @param cur Bounded source cursor at the block header.
    /// @return host Full-width host value.
    /// @return account Encoded account identifier.
    /// @return asset Encoded asset identifier.
    /// @return amount Full-width amount.
    /// @return nextCur Advanced source preserving its end and metadata.
    function unpackHostAccountAmount(uint cur) internal pure returns (uint host, bytes32 account, bytes32 asset, uint amount, uint nextCur) {
        bytes32 a;
        bytes32 b;
        (a, account, asset, b, nextCur) = unpack128(cur, Keys.HostAccountAmount);
        host = uint(a);
        amount = uint(b);
    }

    /// @notice Decode POSITIONCONSTRAINTS without enforcing its quantity constraints.
    /// @dev Validates header and containment once, then copies the full-width fields into the struct.
    function unpackPositionConstraints(uint cur) internal pure returns (PositionConstraints memory value, uint nextCur) {
        uint abs = uint32(cur);
        expectHeader(abs, Headers.PositionConstraints);
        nextCur = advance(cur, 8 + 128);
        assembly ("memory-safe") {
            calldatacopy(value, add(abs, 8), 128)
        }
    }

    /// @notice Decode POSITION and return the advanced source cursor.
    /// @dev Reuses the fixed-word decoder's exact header and containment checks.
    /// @param cur Bounded source cursor at the block header.
    /// @return asset Decoded payload value.
    /// @return amount Decoded payload value.
    /// @return liability Decoded payload value.
    /// @return debt Decoded payload value.
    /// @return counterparty Decoded payload value.
    /// @return nextCur Advanced source preserving its end and metadata.
    function unpackPosition(uint cur) internal pure returns (bytes32 asset, uint amount, bytes32 liability, uint debt, bytes32 counterparty, uint nextCur) {
        bytes32 a;
        bytes32 b;
        (asset, a, liability, b, counterparty, nextCur) = unpack160(cur, Keys.Position);
        amount = uint(a);
        debt = uint(b);
    }

    // Composite blocks: fixed fields followed by validated child cursors.

    /// @notice Decode RELAY's input and continuation BYTES children.
    /// @dev Validates the parent once. The final child proves both children fit
    /// and consume the parent exactly; malformed children revert InvalidBlock.
    /// @param cur Bounded source cursor positioned at the RELAY header.
    /// @return inputCur Clean cursor over the first BYTES payload.
    /// @return stepsCur Clean cursor over the final BYTES payload; its end is RELAY's end.
    /// @return nextCur Advanced source cursor preserving its original end and metadata.
    function unpackRelay(uint cur) internal pure returns (uint inputCur, uint stepsCur, uint nextCur) {
        uint abs = uint32(cur);
        unchecked {
            nextCur = advance(cur, 8 + expectKey(abs, Keys.Relay));
            (inputCur, stepsCur) = pair(abs + 8, uint32(nextCur), Keys.Bytes);
        }
    }

    /// @notice Decode ANNOTATION and retain its final BYTES payload as a cursor.
    /// @dev Checks the parent once; exact final-child validation also proves the fixed prefix fits.
    /// Returned child ranges are clean; the advanced source retains its end and metadata.
    function unpackAnnotation(uint cur) internal pure returns (uint entity, uint dataCur, uint nextCur) {
        uint abs = uint32(cur);
        unchecked {
            nextCur = advance(cur, 8 + expectKey(abs, Keys.Annotation));
            abs += 8;
            entity = uint(read32(abs));
            dataCur = tail(abs + 32, uint32(nextCur), Keys.Bytes);
        }
    }

    /// @notice Decode LABEL and retain its final STRING payload as a cursor.
    /// @dev Checks the parent once; exact final-child validation also proves the fixed prefix fits.
    /// Returned child ranges are clean; the advanced source retains its end and metadata.
    function unpackLabel(uint cur) internal pure returns (bytes32 namespace, uint nameCur, uint nextCur) {
        uint abs = uint32(cur);
        unchecked {
            nextCur = advance(cur, 8 + expectKey(abs, Keys.Label));
            abs += 8;
            namespace = read32(abs);
            nameCur = tail(abs + 32, uint32(nextCur), Keys.String);
        }
    }

    /// @notice Decode SCHEMA and retain its final STRING payload as a cursor.
    /// @dev Checks the parent once; exact final-child validation also proves the fixed prefix fits.
    /// Returned child ranges are clean; the advanced source retains its end and metadata.
    function unpackSchema(uint cur) internal pure returns (uint spec, uint bodyCur, uint nextCur) {
        uint abs = uint32(cur);
        unchecked {
            nextCur = advance(cur, 8 + expectKey(abs, Keys.Schema));
            abs += 8;
            spec = uint(read32(abs));
            bodyCur = tail(abs + 32, uint32(nextCur), Keys.String);
        }
    }

    /// @notice Decode CONTEXT's account and its state/input BYTES children.
    /// @dev Final-child validation proves the fixed account word and both children
    /// fit before the account is loaded. Child shape failures revert InvalidBlock.
    /// @param cur Bounded source cursor positioned at the CONTEXT header.
    /// @return account Encoded account identifier; no account semantics are checked.
    /// @return stateCur Clean cursor over the first BYTES payload.
    /// @return inputCur Clean cursor over the final BYTES payload; its end is CONTEXT's end.
    /// @return nextCur Advanced source cursor preserving its original end and metadata.
    function unpackContext(
        uint cur
    ) internal pure returns (bytes32 account, uint stateCur, uint inputCur, uint nextCur) {
        uint abs = uint32(cur);
        unchecked {
            nextCur = advance(cur, 8 + expectKey(abs, Keys.Context));
            // Children first saves 9 gas/block in the viaIR consuming-loop benchmark.
            (stateCur, inputCur) = pair(abs + 40, uint32(nextCur), Keys.Bytes);
        }
        assembly ("memory-safe") {
            account := calldataload(add(abs, 8))
        }
    }

    /// @notice Decode STEP's words and input, returning the advanced source cursor.
    /// @dev Reuses the parent and final-child validation primitives without rechecking bounds.
    /// The returned input range is independent of the enclosing source cursor.
    /// @param cur Bounded source cursor positioned at the STEP header.
    /// @return cmd Encoded command identifier.
    /// @return value Unsigned native value.
    /// @return inputCur Clean cursor over the final BYTES payload only.
    /// @return nextCur Source cursor after STEP, retaining its original end and metadata.
    function unpackStep(uint cur) internal pure returns (uint cmd, uint value, uint inputCur, uint nextCur) {
        uint abs = uint32(cur);
        unchecked {
            nextCur = advance(cur, 8 + expectKey(abs, Keys.Step));
            abs += 8;
            // Tail first saves 3 gas/block in minimal viaIR consuming loops.
            inputCur = tail(abs + 64, uint32(nextCur), Keys.Bytes);
            cmd = uint(read32(abs));
            value = uint(read32(abs + 32));
        }
    }

    /// @notice Decode CALL and retain its final BYTES payload as a cursor.
    /// @dev Checks the parent once; exact final-child validation also proves the fixed prefix fits.
    /// Returned child ranges are clean; the advanced source retains its end and metadata.
    function unpackCall(uint cur) internal pure returns (uint target, uint value, uint payloadCur, uint nextCur) {
        uint abs = uint32(cur);
        unchecked {
            nextCur = advance(cur, 8 + expectKey(abs, Keys.Call));
            abs += 8;
            target = uint(read32(abs));
            value = uint(read32(abs + 32));
            payloadCur = tail(abs + 64, uint32(nextCur), Keys.Bytes);
        }
    }

    /// @notice Decode DISPATCH and retain its final BYTES payload as a cursor.
    /// @dev Checks the parent once; exact final-child validation also proves the fixed prefix fits.
    /// Returned child ranges are clean; the advanced source retains its end and metadata.
    function unpackDispatch(uint cur) internal pure returns (uint portal, uint resources, uint payloadCur, uint nextCur) {
        uint abs = uint32(cur);
        unchecked {
            nextCur = advance(cur, 8 + expectKey(abs, Keys.Dispatch));
            abs += 8;
            portal = uint(read32(abs));
            resources = uint(read32(abs + 32));
            payloadCur = tail(abs + 64, uint32(nextCur), Keys.Bytes);
        }
    }

    /// @notice Decode RECOVER and retain its final BYTES payload as a cursor.
    /// @dev Checks the parent once; exact final-child validation also proves the fixed prefix fits.
    /// Returned child ranges are clean; the advanced source retains its end and metadata.
    function unpackRecover(uint cur) internal pure returns (uint handler, uint value, bytes32 key, uint witnessCur, uint nextCur) {
        uint abs = uint32(cur);
        unchecked {
            nextCur = advance(cur, 8 + expectKey(abs, Keys.Recover));
            abs += 8;
            handler = uint(read32(abs));
            value = uint(read32(abs + 32));
            key = read32(abs + 64);
            witnessCur = tail(abs + 96, uint32(nextCur), Keys.Bytes);
        }
    }

    /// @notice Check LIMITS against full-width quantities and advance the source.
    /// @dev Validates header and containment once. The high 128 bits are the inclusive
    /// minimum amount; the low 128 bits are the literal inclusive maximum debt.
    function expectLimits(uint cur, uint amount, uint debt) internal pure returns (uint nextCur) {
        uint limits;
        (limits, nextCur) = unpackLimits(cur);
        if (amount < (limits >> 128) || debt > uint128(limits)) revert OutOfRange();
    }

    /// @notice Check BALANCE_CONSTRAINTS against a balance and advance the source cursor.
    /// @dev Validates the exact header, containment, asset, then inclusive full-width
    /// quantity bounds, once each in that order. Zero maximum is literal, not unbounded.
    /// Reverts InvalidBlock for a header mismatch, OutOfBounds for failed containment,
    /// UnexpectedValue for an asset mismatch, or OutOfRange for a quantity violation.
    /// @param cur Bounded source cursor positioned at the constraints header.
    /// @param asset Expected balance asset identifier.
    /// @param amount Full-width balance amount to check against both bounds.
    /// @return nextCur Advanced source cursor preserving its original end and metadata.
    function expectBalanceConstraints(uint cur, bytes32 asset, uint amount) internal pure returns (uint nextCur) {
        uint abs = uint32(cur);
        expectHeader(abs, Headers.BalanceConstraints);
        nextCur = advance(cur, 8 + 96);
        unchecked {
            checkBalanceConstraints(abs + 8, asset, amount);
        }
    }

    /// @notice Check POSITION_CONSTRAINTS directly against a position.
    /// @dev Validates the exact header, containment, identifiers, then inclusive
    /// quantity bounds, in that order. Does not allocate a constraints struct,
    /// modify the position or check its counterparty. Returns the advanced source
    /// cursor for the caller to assign, preserving its original end and metadata.
    /// Identifier mismatch reverts UnexpectedValue; a quantity violation reverts
    /// OutOfRange. Zero maximum debt is a literal zero, not an unbounded sentinel.
    /// @param cur Bounded source cursor positioned at the constraints header.
    /// @param position Position whose exact identifiers and full-width amounts are checked.
    /// @return nextCur Source cursor positioned immediately after the constraints block.
    function expectPositionConstraints(uint cur, Position memory position) internal pure returns (uint nextCur) {
        uint abs = uint32(cur);
        expectHeader(abs, Headers.PositionConstraints);
        nextCur = advance(cur, 8 + 128);
        unchecked {
            checkPositionConstraints(abs + 8, position);
        }
    }
}
