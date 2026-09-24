// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

import {Keys} from "../codec/Keys.sol";
import {max24} from "../utils/Utils.sol";

/// @title Sizes
/// @notice Total byte sizes for fixed-width block types, including the 8-byte header (4-byte key + 4-byte payloadLen).
library Sizes {
    /// @dev Shared block header size: 4-byte key + 4-byte payload length.
    uint constant Header = 8;
    /// @dev One fixed-width payload word.
    uint constant Word = 32;
    /// @dev 8 header + 32 payload = 40 bytes total.
    uint constant B32 = Header + Word;
    /// @dev 8 header + 64 payload = 72 bytes total.
    uint constant B64 = Header + 2 * Word;
    /// @dev 8 header + 96 payload = 104 bytes total.
    uint constant B96 = Header + 3 * Word;
    /// @dev 8 header + 128 payload = 136 bytes total.
    uint constant B128 = Header + 4 * Word;
    /// @dev 8 header + 160 payload = 168 bytes total.
    uint constant B160 = Header + 5 * Word;
    /// @dev Minimum STEP size: 8 header + 32 command + 32 value + 8 nested BYTES header.
    uint constant Step = 2 * Header + 2 * Word;
    /// @dev STATUS block: 8 header + 32 status code = 40 bytes
    uint constant Status = B32;

    // Live pipeline state

    /// @dev BALANCE block: 8 header + 32 asset + 32 amount = 72 bytes
    uint constant Balance = B64;
    /// @dev CUSTODY block: 8 header + 32 host + 32 asset + 32 amount = 104 bytes
    uint constant Custody = B96;
    /// @dev POSITION block: 8 header + five-word position = 168 bytes
    uint constant Position = B160;

    // Input and structural blocks

    /// @dev LIMITS block: 8 header + 32 amount + 32 debt = 72 bytes.
    uint constant Limits = B64;

    /// @dev QUOTE block: 8 header + five-word outcome = 168 bytes.
    uint constant Quote = B160;

    /// @dev BOOTSTRAP block: 8 header + 32 asset + 32 amount + 32 budget = 104 bytes
    uint constant Bootstrap = B96;
    /// @dev AMOUNT block: 8 header + 32 asset + 32 amount = 72 bytes
    uint constant Amount = B64;
    /// @dev HOST_ASSET block: 8 header + 32 host + 32 asset = 72 bytes
    uint constant HostAsset = B64;
    /// @dev Three-word host amount block: 8 header + 32 host + 32 asset + 32 amount = 104 bytes
    uint constant HostAmount = B96;
    /// @dev TRANSACTION block: 8 header + 32 from + 32 to + 32 asset + 32 amount = 136 bytes
    uint constant Transaction = B128;
}

/// @title Specs
/// @notice Word-aligned block specifications encoded as
/// `[key:4][min:4][max:4][hint:3][reserved:17]`.
/// The upper eight bytes of a fixed-layout spec are its encoded block header,
/// allowing the entire spec word to be written directly as that header.
/// A maximum of zero means the payload size is unbounded.
library PreviousSpecs {
    /// @dev A payload is incompatible with its block specification.
    error InvalidSpec();
    uint private constant SizeFields = (uint(1) << 192) | (uint(1) << 160) | (uint(1) << 136);

    // Reusable field shapes keep public specs readable while remaining valid
    // compile-time constant expressions.
    uint private constant Exact32 = 32 * SizeFields;
    uint private constant Exact64 = 64 * SizeFields;
    uint private constant Exact96 = 96 * SizeFields;
    uint private constant Exact128 = 128 * SizeFields;
    uint private constant Exact160 = 160 * SizeFields;
    uint private constant UnboundedHint128 = uint(128) << 136;
    uint private constant UnboundedMin16Hint256 = (uint(16) << 192) | (uint(256) << 136);
    uint private constant UnboundedMin40Hint256 = (uint(40) << 192) | (uint(256) << 136);
    uint private constant UnboundedMin72Hint256 = (uint(72) << 192) | (uint(256) << 136);
    uint private constant UnboundedMin48Hint512 = (uint(48) << 192) | (uint(512) << 136);
    uint private constant UnboundedMin104Hint256 = (uint(104) << 192) | (uint(256) << 136);

    // Empty and reserved blocks

    uint constant Empty = uint(bytes32(Keys.Empty));
    uint constant List = uint(bytes32(Keys.List)) | UnboundedHint128;
    uint constant Bytes = uint(bytes32(Keys.Bytes)) | UnboundedHint128;
    uint constant String = uint(bytes32(Keys.String)) | UnboundedHint128;

    // Live pipeline state

    uint constant Balance = uint(bytes32(Keys.Balance)) | Exact64;
    uint constant Custody = uint(bytes32(Keys.Custody)) | Exact96;
    uint constant Position = uint(bytes32(Keys.Position)) | Exact160;

    // Input and value blocks

    uint constant Limits = uint(bytes32(Keys.Limits)) | Exact64;
    uint constant Quote = uint(bytes32(Keys.Quote)) | Exact160;

    uint constant Amount = uint(bytes32(Keys.Amount)) | Exact64;
    uint constant Bootstrap = uint(bytes32(Keys.Bootstrap)) | Exact96;
    uint constant Allocation = uint(bytes32(Keys.Allocation)) | Exact96;
    uint constant Allowance = uint(bytes32(Keys.Allowance)) | Exact96;
    uint constant Account = uint(bytes32(Keys.Account)) | Exact32;
    uint constant Transaction = uint(bytes32(Keys.Transaction)) | Exact128;

    // Composite and annotation blocks

    uint constant Step = uint(bytes32(Keys.Step)) | UnboundedMin72Hint256;
    uint constant Relay = uint(bytes32(Keys.Relay)) | UnboundedMin16Hint256;
    uint constant Context = uint(bytes32(Keys.Context)) | UnboundedMin48Hint512;
    uint constant Recover = uint(bytes32(Keys.Recover)) | UnboundedMin104Hint256;
    uint constant Dispatch = uint(bytes32(Keys.Dispatch)) | UnboundedMin72Hint256;
    uint constant Call = uint(bytes32(Keys.Call)) | UnboundedMin72Hint256;
    uint constant Asset = uint(bytes32(Keys.Asset)) | Exact32;
    uint constant Node = uint(bytes32(Keys.Node)) | Exact32;
    uint constant Label = uint(bytes32(Keys.Label)) | UnboundedMin40Hint256;
    uint constant Annotation = uint(bytes32(Keys.Annotation)) | UnboundedMin40Hint256;
    uint constant Action = uint(bytes32(Keys.Action)) | Exact32;
    uint constant Counterparty = uint(bytes32(Keys.Counterparty)) | Exact32;
    uint constant Schema = uint(bytes32(Keys.Schema)) | UnboundedMin40Hint256;

    uint constant Status = uint(bytes32(Keys.Status)) | Exact32;
    uint constant AssetLiability = uint(bytes32(Keys.AssetLiability)) | Exact64;
    uint constant AccountAsset = uint(bytes32(Keys.AccountAsset)) | Exact64;
    uint constant HostAsset = uint(bytes32(Keys.HostAsset)) | Exact64;
    uint constant AccountAmount = uint(bytes32(Keys.AccountAmount)) | Exact96;
    uint constant HostAmount = uint(bytes32(Keys.HostAmount)) | Exact96;
    uint constant HostAccountAsset = uint(bytes32(Keys.HostAccountAsset)) | Exact96;
    uint constant HostAccountAmount = uint(bytes32(Keys.HostAccountAmount)) | Exact128;

    /// @notice Construct a block specification from its encoded fields.
    /// @param blockkey Encoded block key.
    /// @param min Minimum accepted payload length.
    /// @param max Maximum accepted payload length; zero means unbounded.
    /// @param hint Initial per-block payload capacity.
    /// @return spec Packed block specification.
    function create(bytes4 blockkey, uint32 min, uint32 max, uint32 hint) internal pure returns (uint spec) {
        return create(uint32(blockkey), min, max, hint);
    }

    /// @notice Construct a block specification from its numeric key and encoded fields.
    /// @param blockkey Numeric block key.
    /// @param min Minimum accepted payload length.
    /// @param max Maximum accepted payload length; zero means unbounded.
    /// @param hint Initial per-block payload capacity.
    /// @return spec Packed block specification.
    function create(uint32 blockkey, uint32 min, uint32 max, uint32 hint) internal pure returns (uint spec) {
        spec |= uint(blockkey) << 224;
        spec |= uint(min) << 192;
        spec |= uint(max) << 160;
        spec |= uint(max24(hint)) << 136;
    }

    /// @notice Construct an exact-size block specification from a numeric key.
    /// @dev Sets the minimum, maximum, and allocation hint to `size`.
    /// @param blockkey Numeric block key.
    /// @param size Exact payload length and initial per-block payload capacity.
    /// @return spec Packed exact-size block specification.
    function create(uint32 blockkey, uint32 size) internal pure returns (uint spec) {
        return create(blockkey, size, size, size);
    }

    /// @notice Decode the block key and accepted payload range from `spec`.
    /// @param spec Packed block specification.
    /// @return blockkey Encoded block key.
    /// @return min Minimum accepted payload length.
    /// @return max Maximum accepted payload length; zero means unbounded.
    function decode(uint spec) internal pure returns (bytes4 blockkey, uint32 min, uint32 max) {
        blockkey = bytes4(uint32(spec >> 224));
        min = uint32(spec >> 192);
        max = uint32(spec >> 160);
    }

    /// @notice Return the block key encoded in `spec`.
    /// @param spec Packed block specification.
    /// @return Encoded block key.
    function key(uint spec) internal pure returns (bytes4) {
        return bytes4(uint32(spec >> 224));
    }

    /// @notice Return whether a payload size lies within a specification's bounds.
    /// @param spec Packed block specification.
    /// @param size Payload length to test.
    /// @return Whether the payload length is accepted.
    function accepts(uint spec, uint size) internal pure returns (bool) {
        uint32 min = uint32(spec >> 192);
        uint32 max = uint32(spec >> 160);
        return size >= min && (max == 0 || size <= max);
    }

    /// @notice Return whether a keyed payload matches a block specification.
    /// @param spec Packed block specification.
    /// @param blockkey Block key to test.
    /// @param size Payload length to test.
    /// @return Whether both the key and payload length are accepted.
    function matches(uint spec, bytes4 blockkey, uint size) internal pure returns (bool) {
        uint32 min = uint32(spec >> 192);
        uint32 max = uint32(spec >> 160);
        return uint32(blockkey) == uint32(spec >> 224) && size >= min && (max == 0 || size <= max);
    }

    /// @notice Validate a payload size against a specification's bounds.
    /// @param spec Packed block specification.
    /// @param size Payload length to validate.
    function validate(uint spec, uint size) internal pure {
        if (!accepts(spec, size)) revert InvalidSpec();
    }

    /// @notice Return an exact payload size constrained to an accepted range.
    /// @param spec Packed block specification.
    /// @param min Smallest exact size accepted by the caller.
    /// @param max Largest exact size accepted by the caller.
    /// @return size Exact payload size encoded by the specification.
    function exact(uint spec, uint min, uint max) internal pure returns (uint size) {
        size = uint32(spec >> 192);
        if (size != uint32(spec >> 160) || size < min || size > max) revert InvalidSpec();
    }

    /// @notice Return estimated bytes per block, including its header; zero for EMPTY.
    /// @param spec Packed block specification.
    /// @return Estimated encoded size, using the payload hint for variable-size specs.
    function blockSize(uint spec) internal pure returns (uint) {
        return key(spec) == bytes4(0) ? 0 : Sizes.Header + uint24(spec >> 136);
    }

    /// @notice Return the initial buffer capacity for `count` blocks of `spec`.
    /// @param spec Packed block specification.
    /// @param count Number of top-level blocks to allocate.
    /// @return capacity Initial encoded byte capacity.
    function allocation(uint spec, uint count) internal pure returns (uint capacity) {
        capacity = count * blockSize(spec);
    }
}
