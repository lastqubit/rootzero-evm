// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

import {Logs} from "../codec/Logs.sol";
import {Codes} from "../utils/Codes.sol";
import {Encoder} from "../codec/Encoder.sol";

/// @title CounterpartyAnnot
/// @notice Associates an entity with an account as counterparty.
/// @dev The latest trusted annotation replaces the earlier value. Zero identifies
/// Rootzero. Consumers validate the claim; an annotation grants no authority.
abstract contract CounterpartyAnnot {
    /// @notice Attach a counterparty account to `entity`.
    /// @param entity Entity receiving the annotation.
    /// @param account Counterparty account ID, or zero for Rootzero.
    function annotateCounterparty(uint entity, bytes32 account) internal virtual {
        Logs.annotation(entity, Encoder.createCounterparty(account), Codes.HostAnnotate);
    }
}
