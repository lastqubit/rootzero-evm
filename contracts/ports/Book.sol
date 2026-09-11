// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

import {PortBase} from "./Base.sol";
import {BookHook} from "../core/Settlement.sol";
import {Sizes, Specs} from "../codec/Specs.sol";
import {Execution, Executions} from "../execution/Execution.sol";

using Executions for Execution;

/// @title BookPort
/// @notice Apply peer-supplied debit/credit pairs through the book hook.
/// @dev Each unnamed local input parent contains two ACCOUNT_AMOUNT blocks: liability debit first,
/// asset credit second. Accounts may differ. Any failure reverts the entire call.
abstract contract BookPort is PortBase, BookHook {
    string private constant INPUT = "#accountAmount as (debit, credit)";
    uint private immutable inputSpec = schema(1, uint32(2 * Sizes.B96), INPUT, "");
    uint private immutable descriptor;

    constructor() {
        (, descriptor) = port("portBook", inputSpec, Specs.Empty, 0);
    }

    /// @notice Debit then credit each input parent's ACCOUNT_AMOUNT pair.
    /// @dev Entering the exact 208-byte parent payload and consuming two 104-byte
    /// children lands exactly at the next parent, so no additional end check is needed.
    /// Both blocks are decoded before calling book. Zero amounts skip their
    /// respective legs; account validation belongs to the host. Empty batches are accepted.
    /// @param data Local input parents containing debit account/liability/debt then credit account/asset/amount.
    /// @return Empty response bytes.
    /// @return Zero native budget credit.
    function portBook(bytes calldata data) external onlyPeer returns (bytes memory, uint) {
        Execution memory exec = openInput(data, descriptor);

        while (exec.more()) {
            exec.enter(inputSpec);
            (bytes32 from, bytes32 liability, uint debt) = exec.unpackAccountAmount();
            (bytes32 to, bytes32 asset, uint amount) = exec.unpackAccountAmount();
            book(from, to, asset, amount, liability, debt);
        }

        return exec.close();
    }
}
