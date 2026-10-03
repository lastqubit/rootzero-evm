// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

import {Blocks} from "../codec/Blocks.sol";
import {PortBase} from "./Base.sol";
import {Flags} from "../utils/Flags.sol";
import {PipeHook} from "../core/Pipeline.sol";
import {CashinHook} from "../core/Cash.sol";
import {Specs} from "../Codec.sol";
import {Execution, Executions} from "../execution/Execution.sol";

using Executions for Execution;
using Blocks for uint;

// Canonical selector of the payable pipeline port.
bytes4 constant PortPipePayableSelector = bytes4(keccak256("portPipePayable(bytes)"));

/// @title PipePayablePort
/// @notice Port that consumes CONTEXT blocks and executes each input as a step stream.
/// Each context's input bytes are passed to the shared pipeline.
abstract contract PipePayablePort is PortBase, PipeHook, CashinHook {
    uint private immutable descriptor;
    uint private immutable id;

    constructor() {
        (id, descriptor) = port("portPipePayable", Specs.Context, Specs.Empty, Flags.Funded);
    }

    /// @notice Execute peer-supplied contexts through the shared payable pipe.
    /// @dev All contexts share the peer call's native-value budget. Any remainder
    /// is credited through `cashin` if the last context's account is nonzero.
    /// Empty input or a zero final account skips cashin and returns the remainder as
    /// budget credit without transferring native value back. A zero budget skips cashin.
    /// The peer owns supplied account validity; no repeated format check is required.
    /// @param data CONTEXT block stream supplied by the trusted peer.
    /// @return Empty response bytes.
    /// @return Remaining budget credit when the final account is zero; otherwise zero.
    function portPipePayable(bytes calldata data) external payable onlyPeer returns (bytes memory, uint) {
        Execution memory exec = openInput(data, descriptor);

        exec.logInput(id, descriptor);
        bytes32 account;
        while (exec.more()) {
            uint stateCur;
            uint inputCur;
            (account, stateCur, inputCur) = exec.unpackContext();
            exec.budget = pipe(account, stateCur.toBytes(), inputCur, exec.budget);
        }

        if (account != bytes32(0) && exec.budget != 0) cashin(account, exec.drainBudget());

        return exec.close(id, descriptor);
    }
}
