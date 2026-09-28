// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

import {AdminBase, Execution, Executions, Flags, Specs} from "./Base.sol";
import {Execute} from "../../codec/Execute.sol";
import {Sizes} from "../../codec/Specs.sol";
import {UnexpectedState} from "../../utils/Errors.sol";
using Executions for Execution;

/// @title Authorize
/// @notice Admin command that grants authorization to a list of node IDs.
/// Each NODE block in the input is authorized on the host.
/// Only callable by the admin account.
abstract contract Authorize is AdminBase {
    uint private immutable descriptor;
    uint private immutable id;

    constructor() {
        (id, descriptor) = command("authorize", Specs.Empty, Specs.Node, Specs.Empty, Flags.Admin);
    }

    /// @notice Return the registered AUTHORIZE command ID.
    function authorizeId() internal view returns (uint) {
        return id;
    }

    /// @notice Authorize each NODE block in the admin input.
    /// @param context Admin command context carrying the NODE input stream.
    /// @return Empty output state.
    /// @return Zero native budget credit.
    function authorize(
        bytes calldata context
    ) external returns (bytes memory, uint) {
        return runAdminCommand(context, descriptor, authorizeOne);
    }

    function authorizeOne(Execution memory exec) private {
        uint node = exec.unpackNode();
        authorizeNode(node);
    }
}

/// @title ExecuteAuthorize
/// @notice Extends Authorize with internal pipeline execution using the same command ID.
/// @dev Uses this host as the caller for admin authorization. With the default Host
/// policy, this requires a self-managed host. Pipeline entrypoints must authenticate
/// the account and prevent peers from supplying the admin account.
abstract contract ExecuteAuthorize is Authorize {
    /// @notice Authorize each NODE input block from an internal pipeline.
    /// @param account Authenticated pipeline account, required to be the admin.
    /// @param state Empty command state.
    /// @param inputCur Cursor over NODE block stream.
    /// @param value Assigned native value, returned unused as credit.
    /// @return handled Always true after successful execution.
    /// @return output Empty output state.
    /// @return credit Unused assigned native value.
    function executeAuthorize(
        bytes32 account,
        bytes memory state,
        uint inputCur,
        uint value
    ) internal returns (bool handled, bytes memory output, uint credit) {
        enforceAdmin(account, address(this));
        if (state.length != 0) revert UnexpectedState();

        (uint abs, uint end) = Execute.bounds(inputCur, Sizes.B32);
        while (abs < end) {
            authorizeNode(Execute.unpackNode(abs));
            unchecked {
                abs += Sizes.B32;
            }
        }

        return (true, "", value);
    }
}
