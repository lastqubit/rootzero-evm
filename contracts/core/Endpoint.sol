// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

import {Execution, Executions} from "../execution/Execution.sol";
import {Logs} from "../codec/Logs.sol";
import {SchemaAnnot} from "../annotations/Schema.sol";

using Executions for Execution;

/// @title EndpointBase
/// @notice Shared endpoint metadata helpers.
abstract contract EndpointBase is SchemaAnnot {
    /// @notice Create and publish endpoint identity, specs and name.
    /// @param id Endpoint node ID.
    /// @param name Human-readable endpoint registration name.
    /// @param state State block spec or named lane.
    /// @param input Input block spec or named lane.
    /// @param output Output block spec or named lane.
    /// @return descriptor Packed execution allocation hints and explicit logging selections.
    function endpoint(
        uint id,
        string memory name,
        uint state,
        uint input,
        uint output
    ) internal returns (uint descriptor) {
        descriptor = Executions.describe(state, input, output, uint8(id >> 224));
        Logs.endpoint(id, state, input, output, name);
    }
}

/// @title InputEndpointBase
/// @notice Shared input opening for endpoint families that have only an input source.
/// Commands intentionally do not inherit this base because they must open state
/// and input together through `openCommand`.
abstract contract InputEndpointBase is EndpointBase {
    /// @notice Open a bounded endpoint input stream.
    function openInput(bytes calldata input, uint descriptor) internal view returns (Execution memory exec) {
        exec.openInput(descriptor, msg.value, input);
    }
}
