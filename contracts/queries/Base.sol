// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

import {InputEndpointBase} from "../core/Endpoint.sol";
import {Execution, Executions} from "../execution/Execution.sol";
import {Lanes} from "../codec/Lanes.sol";
import {Specs} from "../codec/Specs.sol";
import {Nodes} from "../utils/Nodes.sol";

using Executions for Execution;

/// @title QueryBase
/// @notice Abstract base for rootzero query contracts.
/// Queries are view-only entry points that consume a block-stream input and
/// return a block-stream response.
abstract contract QueryBase is InputEndpointBase {

    /// @notice Publish query metadata and a default label.
    /// @param name Query entrypoint name and default label. It must exactly
    /// match the Solidity query function name used by the canonical ABI.
    /// @param input Input spec; query lane codes must be zero.
    /// @param output Output spec; query lane codes must be zero.
    /// @return id Query node ID.
    /// @return descriptor Packed execution allocation hints and lane-derived logging selections.
    function query(
        string memory name,
        uint input,
        uint output
    ) internal returns (uint id, uint descriptor) {
        if (Lanes.codes(input) != 0 || Lanes.codes(output) != 0) revert Specs.InvalidSpec();
        id = Nodes.toQuery(name, address(this), 0);
        descriptor = endpoint(id, name, Specs.Empty, input, output);
    }

    /// @notice Query an input stream through a view callback per item.
    /// @dev Opens raw input with no account, state, or native-value budget.
    /// The callback may read contract state and update execution memory, and must
    /// advance input on each iteration. Empty input invokes no callback. No
    /// progress guard is enforced. Callbacks must preserve bounded cursors;
    /// finalization does not recheck them. Queries cannot emit logs.
    /// @param descriptor Packed input-only endpoint descriptor.
    /// @param input Input block stream.
    /// @param process Internal view callback that consumes and answers one item.
    /// @return output Final encoded response block stream.
    function runQuery(
        uint descriptor,
        bytes calldata input,
        function(Execution memory) internal view process
    ) internal view returns (bytes memory output) {
        Execution memory exec;
        exec.openInput(descriptor, 0, input);
        while (exec.more()) {
            process(exec);
        }
        return exec.finish();
    }
}
