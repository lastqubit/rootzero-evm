// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

import {PortBase} from "./Base.sol";
import {PostHook} from "../core/Settlement.sol";
import {Specs} from "../Codec.sol";
import {Execution, Executions} from "../execution/Execution.sol";
import {ActionAnnot} from "../annotations/Action.sol";
import {Actions} from "../utils/Actions.sol";

using Executions for Execution;

/// @title PostPort
/// @notice Port that posts peer-supplied TRANSACTION blocks through debit and credit hooks.
/// Each TRANSACTION block calls `debitAccount` for `from` and `creditAccount` for `to`.
abstract contract PostPort is PortBase, PostHook, ActionAnnot {
    uint private immutable descriptor;

    constructor() {
        uint id;
        (id, descriptor) = port("portPost", Specs.Transaction, Specs.Empty, 0);
        annotateAction(id, Actions.Post);
    }

    /// @notice Post peer-supplied transactions.
    /// @param data TRANSACTION block stream supplied by the trusted peer.
    /// @return Empty response bytes.
    function portPost(bytes calldata data) external onlyPeer returns (bytes memory) {
        Execution memory exec = openInput(data, descriptor);

        while (exec.more()) {
            (bytes32 from, bytes32 to, bytes32 asset, uint amount) = exec.unpackTransaction();
            post(from, to, asset, amount);
        }

        return "";
    }
}
