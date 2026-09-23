// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

import { InputEndpointBase } from "../core/Endpoint.sol";
import { Execution, Executions } from "../execution/Execution.sol";
import { Specs } from "../codec/Specs.sol";
import { Nodes } from "../utils/Nodes.sol";

/// @title QueryBase
/// @notice Abstract base for rootzero query contracts.
/// Queries are view-only entry points that consume a block-stream input and
/// return a block-stream response.
abstract contract QueryBase is InputEndpointBase {

    /// @notice Publish query metadata and a default label.
    /// @param name Query entrypoint name and default label. It must exactly
    /// match the Solidity query function name used by the canonical ABI.
    /// @param input Input block specification.
    /// @param output Output block specification.
    /// @return id Query node ID.
    /// @return descriptor Packed endpoint lane metadata and flags.
    function query(
        string memory name,
        uint input,
        uint output
    ) internal returns (uint id, uint descriptor) {
        descriptor = Executions.describe(Specs.Empty, input, output, 0);
        return query(name, descriptor);
    }

    /// @notice Publish an already constructed query descriptor and default label.
    /// @param name Query entrypoint name and default label. It must exactly
    /// match the Solidity query function name used by the canonical ABI.
    /// @param descriptor Packed query endpoint descriptor.
    /// @return id Query node ID.
    /// @return published Published endpoint descriptor.
    function query(
        string memory name,
        uint descriptor
    ) internal returns (uint id, uint published) {
        id = Nodes.toQuery(name, address(this), uint8(descriptor));
        published = endpoint(id, name, descriptor);
    }

    /// @notice Query an input stream through a view callback per item.
    /// @dev Opens raw input with no account, state, or native-value budget.
    /// The callback may read contract state and update execution memory, and must
    /// advance input on each iteration. Empty input invokes no callback. No
    /// progress guard is enforced.
    /// @param input Input block stream.
    /// @param descriptor Packed input-only endpoint descriptor.
    /// @param process Internal view callback that consumes and answers one item.
    /// @return output Final encoded response block stream.
    function runQuery(
        bytes calldata input,
        uint descriptor,
        function(Execution memory) internal view process
    ) internal view returns (bytes memory output) {
        Execution memory exec;
        Executions.openInput(exec, descriptor, 0, input);
        while (Executions.more(exec)) {
            process(exec);
        }
        return Executions.finish(exec);
    }
}
