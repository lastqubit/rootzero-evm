// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

import {Specs} from "../Codec.sol";
import {Execution, Executions} from "../execution/Execution.sol";
import {QueryBase} from "./Base.sol";

using Executions for Execution;

/// @notice Hook implemented by hosts that expose current entity conditions.
abstract contract GetEntityCodesHook {
    /// @notice Resolve current condition codes for one entity.
    /// @dev Zero means unknown or no condition reported, not explicitly inactive.
    /// Implementations define entity kinds, applicable conditions, and valid code
    /// packing. Return current conditions, not historical actions or effects.
    /// Active/Inactive is optional; when applicable, use one unambiguous state.
    /// The query encodes the returned word unchanged without semantic validation.
    /// @param entity Generic full-width entity identifier, as used by annotations.
    /// @return codes Packed identifiers describing the entity's current condition.
    function entityCodes(uint entity) internal view virtual returns (uint codes);
}

/// @title GetEntityCodes
/// @notice Query current conditions for one or more entities.
/// Input is an ENTITY stream; output is one CODES block per entity in input order.
abstract contract GetEntityCodes is QueryBase, GetEntityCodesHook {
    uint private immutable descriptor;

    constructor() {
        (, descriptor) = query("entityCodes", Specs.Entity, Specs.Codes);
    }

    /// @notice Resolve current conditions for a run of requested entities.
    /// @param input Block stream of entity { uint entity } entries.
    /// @return One codes { uint codes } block per input entry, including zero codes.
    function entityCodes(bytes calldata input) external view returns (bytes memory) {
        return runQuery(input, descriptor, entityCodesOne);
    }

    function entityCodesOne(Execution memory exec) private view {
        exec.outputCodes(entityCodes(exec.unpackEntity()));
    }
}
