// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

import {PortBase} from "./Base.sol";
import {Flags} from "../utils/Flags.sol";
import {PipeHook} from "../core/Pipeline.sol";
import {CashinHook} from "../core/Cash.sol";
import {Specs} from "../Codec.sol";
import {Execution, Executions} from "../execution/Execution.sol";

using Executions for Execution;

// Canonical selector of the payable pipeline port.
bytes4 constant PortPipePayableSelector = bytes4(keccak256("portPipePayable(bytes)"));

/// @title PipePayablePort
/// @notice Port that consumes CONTEXT blocks and executes each input as a step stream.
/// Each context's input bytes are passed to the shared pipeline.
abstract contract PipePayablePort is PortBase, PipeHook, CashinHook {
    uint private immutable descriptor;

    constructor() {
        (, descriptor) = port("portPipePayable", Specs.Context, Specs.Empty, Flags.Funded);
    }

    /// @notice Execute peer-supplied contexts through the shared payable pipe.
    /// @dev All contexts share the peer call's native-value budget. Any remainder
    /// is credited through `cashin` to the last context's account after all pipes.
    /// Empty input with value passes the zero account to `cashin`.
    /// Account validation belongs to the hook. Settlement consumes the remainder,
    /// so no native budget credit is returned to the peer.
    /// @param data CONTEXT block stream supplied by the trusted peer.
    /// @return Empty response bytes.
    /// @return Zero native budget credit.
    function portPipePayable(bytes calldata data) external payable onlyPeer returns (bytes memory, uint) {
        Execution memory exec = openInput(data, descriptor);

        bytes32 account;
        while (exec.more()) {
            bytes calldata state;
            bytes calldata input;
            (account, state, input) = exec.unpackContext();
            exec.budget = pipe(account, state, input, exec.budget);
        }

        if (exec.budget != 0) cashin(account, exec.drainBudget());

        return exec.close();
    }
}
