// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

import {Logs} from "../codec/Logs.sol";
import {Codes} from "../utils/Codes.sol";
import {Encoder} from "../codec/Encoder.sol";

/// @title LabelAnnot
/// @notice Emits standard label annotation blocks for entities.
/// @dev A label is identified by its entity and namespace. For a trusted
/// emitter, the latest label in a namespace replaces the earlier value.
abstract contract LabelAnnot {
    /// @notice Attach a human-readable namespaced label to `entity`.
    /// @param entity Entity receiving the label annotation.
    /// @param namespace Label namespace.
    /// @param name Human-readable name within the namespace.
    function label(uint entity, bytes32 namespace, string memory name) internal virtual {
        Logs.annotation(entity, Encoder.createLabel(namespace, bytes(name)), Codes.HostAnnotate);
    }
}
