// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

import {AdminBase, Execution, Executions, Flags, Specs} from "./Base.sol";
import {Execute} from "../../codec/Execute.sol";
import {Sizes} from "../../codec/Specs.sol";
import {UnexpectedState} from "../../utils/Errors.sol";
using Executions for Execution;

/// @title Authorize
/// @notice Admin command that adds a list of IDs to the host's trusted set.
/// Each ENTITY block in the input is trusted. IDs of any kind are accepted: nodes the
/// host authorizes and, on a commander, assets and other entities in its registry.
/// Only callable by the admin account.
abstract contract Authorize is AdminBase {
    uint private immutable descriptor;
    uint private immutable id;

    constructor() {
        (id, descriptor) = command("authorize", Specs.Empty, Specs.Entity, Specs.Empty, Flags.Admin);
    }

    /// @notice Return the registered AUTHORIZE command ID.
    /// @return Registered command node identifier.
    function authorizeId() internal view returns (uint) {
        return id;
    }

    /// @notice Trust each ENTITY block in the admin input.
    /// @dev The trust hook publishes Trust records for changes.
    /// @param context Admin command context carrying the ENTITY input stream.
    /// @return Empty output state.
    /// @return Zero native budget credit.
    function authorize(
        bytes calldata context
    ) external returns (bytes memory, uint) {
        return runAdmin(descriptor, context, authorizeOne);
    }

    /// @dev Process one ENTITY item for the Authorize endpoint.
    /// @param exec Execution containing the account, source cursors, output writer, and native-value budget.
    function authorizeOne(Execution memory exec) private {
        setTrust(exec.unpackEntity(), true);
    }
}

/// @title ExecuteAuthorize
/// @notice Extends Authorize with internal pipeline execution using the same command ID.
/// @dev Uses this host as the caller for admin authorization. With the default Host
/// policy, this requires a self-managed host. Pipeline entrypoints must authenticate
/// the account and prevent peers from supplying the admin account.
abstract contract ExecuteAuthorize is Authorize {
    /// @notice Trust each ENTITY input block from an internal pipeline.
    /// @param account Authenticated pipeline account, required to be the admin.
    /// @param state Empty command state.
    /// @param inputCur Cursor over ENTITY block stream.
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
            setTrust(Execute.unpackEntity(abs), true);
            unchecked {
                abs += Sizes.B32;
            }
        }

        // The default output is the shared empty bytes value; no allocation is needed.
        return (true, output, value);
    }
}
