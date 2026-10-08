// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

// Frozen LABEL/ANNOTATION support for historical codec tests and benchmarks only.
import {Keys} from "../codec/Keys.sol";
import {Encoder} from "../codec/Encoder.sol";
import {Blocks} from "../codec/Blocks.sol";
import {Execution} from "../execution/Execution.sol";
import {INVALID_BLOCK} from "../utils/Errors.sol";

library PreviousNamingEncoder {
    /// @notice Append LABEL by copying complete validated calldata STRING children.
    /// @dev Children include their headers, are not advanced, and are not revalidated.
    function writeLabel(
        uint cur,
        bytes memory dst,
        bytes32 namespace,
        uint nameCur
    ) internal pure returns (bytes memory value, uint nextCur) {
        uint nameSize = Encoder.length(nameCur);
        uint size = 40 + nameSize;
        uint abs;
        (value, abs, nextCur) = Encoder.reserve(cur, dst, size);
        unchecked {
            abs = Encoder.writeHeader(abs, bytes4(keccak256("#label")), size - 8);
        }
        abs = Encoder.write32(abs, namespace);
        Encoder.copy(abs, uint32(nameCur), nameSize);
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
        (value, abs, nextCur) = Encoder.reserve(cur, dst, size);
        unchecked {
            abs = Encoder.writeHeader(abs, bytes4(keccak256("#label")), size - 8);
        }
        abs = Encoder.write32(abs, namespace);
        Encoder.wrap(abs, Keys.String, name, nameSize);
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
        uint nameSize = Encoder.length(nameCur);
        uint size = 48 + nameSize;
        uint abs;
        (value, abs, nextCur) = Encoder.reserve(cur, dst, size);
        unchecked {
            abs = Encoder.writeHeader(abs, bytes4(keccak256("#label")), size - 8);
        }
        abs = Encoder.write32(abs, namespace);
        Encoder.wrap(abs, Keys.String, uint32(nameCur), nameSize);
    }

    /// @notice Create ANNOTATION around an existing annotation block stream.
    /// @param entity Entity receiving the metadata claims.
    /// @param data Encoded annotation blocks, preserved without interpreting their merge rules.
    /// @return value Complete ANNOTATION block with zero allocation padding.
    function createAnnotation(uint entity, bytes memory data) internal pure returns (bytes memory value) {
        uint size = 48 + data.length;
        value = Encoder.allocate(size);
        unchecked {
            uint abs = Encoder.writeHeader(Encoder.pos(value, 0), bytes4(keccak256("#annotation")), size - 8);
            abs = Encoder.write32(abs, bytes32(entity));
            Encoder.wrap(abs, Keys.Bytes, data, data.length);
        }
    }

    /// @notice Create LABEL by wrapping a memory payload in a STRING child header.
    /// @param namespace Label namespace.
    /// @param name Raw text bytes, excluding the STRING header.
    /// @return value Complete LABEL block with zero allocation padding.
    function createLabel(bytes32 namespace, bytes memory name) internal pure returns (bytes memory value) {
        uint size = 48 + name.length;
        value = Encoder.allocate(size);
        unchecked {
            uint abs = Encoder.writeHeader(Encoder.pos(value, 0), bytes4(keccak256("#label")), size - 8);
            abs = Encoder.write32(abs, namespace);
            Encoder.wrap(abs, Keys.String, name, name.length);
        }
    }
}

library PreviousNamingBlocks {
    /// @notice Decode ANNOTATION and retain its final BYTES payload as a cursor.
    /// @dev Checks the parent once; exact final-child validation also proves the fixed prefix fits.
    /// Returned child ranges are clean; the advanced source retains its end and metadata.
    function unpackAnnotation(uint cur) internal pure returns (uint entity, uint dataCur, uint nextCur) {
        uint abs = uint32(cur);
        unchecked {
            nextCur = Blocks.advance(cur, 8 + expectKey(abs, bytes4(keccak256("#annotation"))));
            abs += 8;
            entity = uint(Blocks.read32(abs));
            dataCur = tail(abs + 32, uint32(nextCur), Keys.Bytes);
        }
    }

    /// @notice Decode LABEL and retain its final STRING payload as a cursor.
    /// @dev Checks the parent once; exact final-child validation also proves the fixed prefix fits.
    /// Returned child ranges are clean; the advanced source retains its end and metadata.
    function unpackLabel(uint cur) internal pure returns (bytes32 namespace, uint nameCur, uint nextCur) {
        uint abs = uint32(cur);
        unchecked {
            nextCur = Blocks.advance(cur, 8 + expectKey(abs, bytes4(keccak256("#label"))));
            abs += 8;
            namespace = Blocks.read32(abs);
            nameCur = tail(abs + 32, uint32(nextCur), Keys.String);
        }
    }

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
}

library PreviousNamingExecutions {
    /// @notice Decode ANNOTATION and retain dynamic payloads as calldata cursors.
    /// @dev Blocks validates and advances input once; returned payload cursors
    /// exclude child headers and have no metadata. Convert only when bytes/text are needed.
    function unpackAnnotation(Execution memory exec) internal pure returns (uint entity, uint dataCur) {
        (entity, dataCur, exec.input) = PreviousNamingBlocks.unpackAnnotation(exec.input);
    }

    /// @notice Decode LABEL and retain dynamic payloads as calldata cursors.
    /// @dev Blocks validates and advances input once; returned payload cursors
    /// exclude child headers and have no metadata. Convert only when bytes/text are needed.
    function unpackLabel(Execution memory exec) internal pure returns (bytes32 namespace, uint nameCur) {
        (namespace, nameCur, exec.input) = PreviousNamingBlocks.unpackLabel(exec.input);
    }

    /// @notice Append a LABEL block to execution output.
    /// @param exec Execution receiving the block.
    /// @param namespace Label namespace to encode.
    /// @param name Label text to encode.
    function outputLabel(Execution memory exec, bytes32 namespace, string memory name) internal pure {
        (exec.buffer, exec.output) = PreviousNamingEncoder.writeLabelWrap(exec.output, exec.buffer, namespace, bytes(name));
    }

    /// @notice Append LABEL from a complete validated STRING block cursor.
    /// @dev Source is not advanced or revalidated; its range must belong to calldata.
    function outputLabel(Execution memory exec, bytes32 namespace, uint nameCur) internal pure {
        (exec.buffer, exec.output) = PreviousNamingEncoder.writeLabel(exec.output, exec.buffer, namespace, nameCur);
    }

    /// @notice Append LABEL from a payload cursor; adds the STRING header.
    /// @dev Source is not advanced or revalidated; its range must belong to calldata.
    function outputLabelWrap(Execution memory exec, bytes32 namespace, uint nameCur) internal pure {
        (exec.buffer, exec.output) = PreviousNamingEncoder.writeLabelWrap(exec.output, exec.buffer, namespace, nameCur);
    }
}
