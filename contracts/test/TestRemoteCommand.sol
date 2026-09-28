// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;
import {LegacyBlocks} from "./LegacyBlocks.sol";

import {Cursors} from "../utils/Cursors.sol";

contract TestRemoteCommand {
    event CommandCalled(bytes4 selector, uint value);

    function respond(
        bytes calldata context,
        uint amount
    ) private pure returns (bytes memory output, uint returnedCredit) {
        (uint abs, ) = Cursors.bounds(context);
        (, bytes calldata state, , ) = LegacyBlocks.unpackContext(abs);
        return (state, amount);
    }

    function noop(bytes calldata context) external payable returns (bytes memory output, uint returnedCredit) {
        emit CommandCalled(msg.sig, msg.value);
        return respond(context, 0);
    }

    function first(bytes calldata context) external payable returns (bytes memory output, uint returnedCredit) {
        emit CommandCalled(msg.sig, msg.value);
        return respond(context, 0);
    }

    function second(bytes calldata context) external payable returns (bytes memory output, uint returnedCredit) {
        emit CommandCalled(msg.sig, msg.value);
        return respond(context, 0);
    }

    function credit(bytes calldata context) external payable returns (bytes memory output, uint returnedCredit) {
        emit CommandCalled(msg.sig, msg.value);
        return respond(context, 123);
    }
}
