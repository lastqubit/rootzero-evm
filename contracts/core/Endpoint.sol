// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

import {Execution, Executions} from "../execution/Execution.sol";
import {Logs} from "../codec/Logs.sol";
import {Codes} from "../utils/Codes.sol";
import {LabelAnnot} from "../annotations/Label.sol";
import {SchemaAnnot} from "../annotations/Schema.sol";

using Executions for Execution;

/// @title EndpointBase
/// @notice Shared endpoint metadata helpers.
abstract contract EndpointBase is SchemaAnnot, LabelAnnot {
    /// @notice Create and publish endpoint metadata with a default label.
    /// @param id Endpoint node ID.
    /// @param name Default human-readable endpoint label.
    /// @param state State lane: upper-half spec and lower-half codes.
    /// @param input Input lane: upper-half spec and lower-half codes.
    /// @param output Output lane: upper-half spec and lower-half codes.
    /// @return descriptor Packed execution allocation hints and lane-derived logging selections.
    function endpoint(
        uint id,
        string memory name,
        uint state,
        uint input,
        uint output
    ) internal returns (uint descriptor) {
        descriptor = Executions.describe(state, input, output);
        Logs.endpoint(id, state, input, output, Codes.HostAdd);
        label(id, bytes32(0), name);
    }
}

/// @title InputEndpointBase
/// @notice Shared input opening for endpoint families that have only an input source.
/// Commands intentionally do not inherit this base because they must open state
/// and input together through `openCommand`.
abstract contract InputEndpointBase is EndpointBase {
    /// @notice Open a bounded endpoint input stream.
    function openInput(
        bytes calldata input,
        uint descriptor
    ) internal view returns (Execution memory exec) {
        exec.openInput(descriptor, msg.value, input);
    }
}
