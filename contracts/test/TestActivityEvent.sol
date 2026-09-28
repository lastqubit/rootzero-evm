// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

import {ActionAnnot} from "../Core.sol";
import {ActivityEvent, Actions, Effects, States, Codes} from "../Events.sol";
import {States as UtilityStates, Effects as UtilityEffects, Codes as UtilityCodes} from "../Utils.sol";

contract TestActivityEvent is ActionAnnot, ActivityEvent {
    function emitActivity(bytes32 account, uint codes, uint id) external {
        emit Activity(account, codes, id);
    }

    function emitExamples(bytes32 account) external {
        emit Activity(account, Actions.None, 0);
        emit Activity(account, Actions.Deposit, 0);
        emit Activity(account, Effects.Lock, 0);
        emit Activity(account, States.Active, 0);
        emit Activity(account, UtilityStates.Inactive, 0);
        emit Activity(account, Codes.AddThenActive, 0);
        emit Activity(account, UtilityCodes.RemoveThenInactive, 0);
        emit Activity(account, Codes.EnableThenActive, 0);
        emit Activity(account, Codes.DisableThenInactive, 0);
        emit Activity(account, Codes.AuthorizeThenActive, 0);
        emit Activity(account, Codes.RevokeThenInactive, 0);
        emit Activity(account, Codes.AppointThenActive, 0);
        emit Activity(account, Codes.DismissThenInactive, 0);
        emit Activity(account, Codes.AllowThenActive, 0);
        emit Activity(account, Codes.DenyThenInactive, 0);
        emit Activity(account, uint(Actions.Swap) | (uint(Actions.Borrow) << 32) |
            (uint(Effects.Spend) << 64) | (uint(Effects.Receive) << 96) |
            (uint(Effects.Lock) << 128) | (uint(UtilityEffects.Unlock) << 160) |
            (uint(States.Active) << 192) | (uint(UtilityStates.Inactive) << 224), 1);
    }
}
