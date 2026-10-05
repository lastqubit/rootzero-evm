// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

import {Logs} from "../codec/Logs.sol";
import {Codes} from "../utils/Codes.sol";
import {Encoder} from "../codec/Encoder.sol";

/// @title ActionAnnot
/// @notice Emits a primary semantic action annotation for an entity.
/// @dev For a trusted emitter, the latest action replaces the earlier value.
abstract contract ActionAnnot {
    /// @notice Attach a primary semantic action to `entity`.
    /// @param entity Entity receiving the action annotation.
    /// @param value Canonical action identifier, such as a value from `Actions`.
    function annotateAction(uint entity, uint value) internal virtual {
        Logs.annotation(entity, Encoder.createAction(value), Codes.HostAnnotate);
    }
}
