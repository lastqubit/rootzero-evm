// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

import {TrustCheck} from "../core/Access.sol";
import {Untrusted} from "../core/Runtime.sol";
import {InvalidBlock} from "../utils/Errors.sol";

/// @dev The commander's `checkTrust()` entrypoint, for test hosts that stand in for a commander.
abstract contract TestTrustRegistry is TrustCheck {
    function checkTrust() external view {
        if ((msg.data.length - 4) % 32 != 0) revert InvalidBlock();
        for (uint p = 4; p < msg.data.length; p += 32) {
            bytes32 id = bytes32(msg.data[p:p + 32]);
            if (!isTrusted(uint(id))) revert Untrusted(id);
        }
    }
}
