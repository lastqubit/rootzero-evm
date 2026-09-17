// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

import {PortBase} from "./Base.sol";
import {GroupsAnnot} from "../annotations/Groups.sol";
import {BookHook} from "../core/Settlement.sol";
import {Specs} from "../codec/Specs.sol";
import {Execution, Executions} from "../execution/Execution.sol";

using Executions for Execution;

/// @title BookPort
/// @notice Apply peer-supplied debit/credit pairs through the book hook.
/// @dev Each input group contains two consecutive ACCOUNT_AMOUNT blocks: liability debit first,
/// asset credit second. Accounts may differ. Any failure reverts the entire call.
abstract contract BookPort is PortBase, BookHook, GroupsAnnot {
    uint private immutable descriptor;

    constructor() {
        uint id;
        (id, descriptor) = port("portBook", Specs.AccountAmount, Specs.Empty, 0);
        annotateGroups(id, "#input as (debit, credit)");
    }

    /// @notice Debit then credit each consecutive ACCOUNT_AMOUNT pair.
    /// @dev Both blocks are decoded before calling book. Zero amounts skip their
    /// respective legs; account validation belongs to the host. Empty batches are accepted.
    /// @param data Flat pairs: debit account/liability/debt then credit account/asset/amount.
    /// @return Empty response bytes.
    /// @return Zero native budget credit.
    function portBook(bytes calldata data) external onlyPeer returns (bytes memory, uint) {
        Execution memory exec = openInput(data, descriptor);

        while (exec.more()) {
            (bytes32 from, bytes32 liability, uint debt) = exec.unpackAccountAmount();
            (bytes32 to, bytes32 asset, uint amount) = exec.unpackAccountAmount();
            book(from, to, asset, amount, liability, debt);
        }

        return exec.close();
    }
}
