// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

import {Execution, Executions} from "../execution/Execution.sol";
import {EndpointEvent} from "../events/Endpoint.sol";
import {LabelAnnot} from "../annotations/Label.sol";
import {SchemaAnnot} from "../annotations/Schema.sol";

using Executions for Execution;

/// @title EndpointBase
/// @notice Shared endpoint metadata helpers.
abstract contract EndpointBase is EndpointEvent, LabelAnnot, SchemaAnnot {
    /// @notice Create and publish endpoint metadata with a default label.
    /// @param id Endpoint node ID.
    /// @param name Default human-readable endpoint label.
    /// @param state State block specification.
    /// @param input Input block specification.
    /// @param output Output block specification.
    /// @param flags Packed endpoint behavior flags.
    /// @return descriptor Packed endpoint lane metadata and flags.
    function endpoint(
        uint id,
        string memory name,
        uint state,
        uint input,
        uint output,
        uint8 flags
    ) internal returns (uint descriptor) {
        descriptor = Executions.describe(state, input, output, flags);
        return endpoint(id, name, descriptor);
    }

    /// @notice Publish already constructed endpoint metadata with a default label.
    /// @param id Endpoint node ID.
    /// @param name Default human-readable endpoint label.
    /// @param descriptor Packed endpoint lane metadata and flags.
    /// @return The published endpoint descriptor.
    function endpoint(uint id, string memory name, uint descriptor) internal returns (uint) {
        emit Endpoint(host, id, descriptor);
        label(id, bytes32(0), name);
        return descriptor;
    }

    /// @notice Finalize an execution output and return its encoded block stream.
    /// @param exec Completed endpoint execution.
    /// @return Encoded output block stream.
    function close(Execution memory exec) internal pure returns (bytes memory) {
        return Executions.finish(exec);
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
