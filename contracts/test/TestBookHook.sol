// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

import {Settle} from "../commands/Settle.sol";
import {Settlement, SettleHook, BookHook} from "../core/Settlement.sol";
import {Position} from "../core/Types.sol";
import {BookPort} from "../ports/Book.sol";
import {Runtime} from "../core/Runtime.sol";
import {AccessDenied} from "../core/Access.sol";

/// @dev Settlement and portBook both route exact legs through a custom BookHook.
contract TestBookHook is Settle, BookPort, Settlement {
    address private immutable tester = msg.sender;
    event Applied(bytes32 from, bytes32 to, bytes32 asset, uint amount, bytes32 liability, uint debt);

    constructor() Runtime(0) {}

    function enforceCaller(address caller) internal view override returns (address) {
        if (caller != tester) revert AccessDenied();
        return caller;
    }

    function enforcePeer(address caller) internal view override returns (address) {
        if (caller != tester) revert AccessDenied();
        return caller;
    }

    function settle(bytes32 account, Position memory position)
        internal override(Settlement, SettleHook)
    {
        Settlement.settle(account, position);
    }

    // The custom book hook handles both legs, so these account hooks are unused.
    function debitAccount(bytes32, bytes32, uint) internal pure override { revert AccessDenied(); }
    function creditAccount(bytes32, bytes32, uint) internal pure override { revert AccessDenied(); }

    function book(bytes32 from, bytes32 to, bytes32 asset, uint amount, bytes32 liability, uint debt)
        internal override(Settlement, BookHook)
    {
        emit Applied(from, to, asset, amount, liability, debt);
    }
}
