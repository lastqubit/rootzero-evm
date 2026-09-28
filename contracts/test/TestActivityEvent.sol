// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

import {ActionAnnot} from "../Core.sol";
import {ActivityEvent, Actions, Effects} from "../Events.sol";
import {Effects as UtilityEffects} from "../Utils.sol";

contract TestActivityEvent is ActionAnnot, ActivityEvent {
    function emitActivity(bytes32 account, uint codes, uint id) external {
        emit Activity(account, codes, id);
    }

    function emitExamples(bytes32 account) external {
        emit Activity(account, Actions.None, 0);
        emit Activity(account, Actions.Deposit, 0);
        emit Activity(account, Effects.Lock, 0);
        emit Activity(account, uint(Actions.Swap) | (uint(Actions.Borrow) << 32) |
            (uint(Effects.Spend) << 64) | (uint(Effects.Receive) << 96) |
            (uint(Effects.Lock) << 128) | (uint(UtilityEffects.Unlock) << 160), 1);
    }
}
