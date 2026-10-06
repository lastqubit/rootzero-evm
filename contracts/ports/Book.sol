// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

import {PortBase} from "./Base.sol";
import {BookHook} from "../core/Settlement.sol";
import {Specs} from "../codec/Specs.sol";
import {Execution, Executions} from "../execution/Execution.sol";

using Executions for Execution;

/// @title BookPort
/// @notice Apply peer-supplied debit/credit pairs through the book hook.
/// @dev Each BOOKING identifies both accounts and asset quantities. Accounts may
/// differ. Any failure reverts the entire call, including hook-emitted logs.
abstract contract BookPort is PortBase, BookHook {
    uint private immutable descriptor;
    uint private immutable id;

    constructor() {
        (id, descriptor) = port("portBook", Specs.Booking, Specs.Empty, 0);
    }

    /// @notice Debit then credit each BOOKING in the input stream.
    /// @dev Both legs are decoded before calling book. Zero amounts skip their
    /// respective legs; supplied account validity belongs to the trusted peer.
    /// The receiving port need not repeat format checks. Empty batches are accepted.
    /// @param data BOOKING stream: from, to, liability, debt, asset, amount.
    /// @return Empty response bytes.
    /// @return Zero native budget credit.
    function portBook(bytes calldata data) external onlyPeer returns (bytes memory, uint) {
        return runPort(id, descriptor, data, portBookOne);
    }

    function portBookOne(Execution memory exec) private {
        book(exec.unpackBooking());
    }
}
