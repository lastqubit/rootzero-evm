// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

import {Book} from "../commands/Book.sol";
import {BookPort} from "../ports/Book.sol";
import {Runtime} from "../core/Runtime.sol";
import {AccessDenied} from "../core/Access.sol";

/// @dev A host can supply only BookHook to compose both booking entrypoints.
contract TestBookHook is Book, BookPort {
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

    function book(bytes32 from, bytes32 to, bytes32 asset, uint amount, bytes32 liability, uint debt)
        internal override
    {
        emit Applied(from, to, asset, amount, liability, debt);
    }
}
