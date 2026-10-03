// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

import {ActionAnnot} from "../Core.sol";
import {ActivityEvent, Actions, Effects, States, Codes} from "../Events.sol";
import {States as UtilityStates, Effects as UtilityEffects, Codes as UtilityCodes} from "../Utils.sol";

contract TestActivityEvent is ActionAnnot, ActivityEvent {
    function emitActivity(bytes32 account, bytes32 subject, uint value, uint codes) external {
        emit Activity(account, subject, value, codes);
    }

    function emitExamples(bytes32 account) external {
        emit Activity(account, bytes32(0), 0, Actions.None);
        emit Activity(account, bytes32(0), 0, Actions.Deposit);
        emit Activity(account, bytes32(0), 0, Effects.Lock);
        emit Activity(account, bytes32(0), 0, States.Active);
        emit Activity(account, bytes32(0), 0, UtilityStates.Inactive);
        emit Activity(account, bytes32(0), 0, Codes.AddThenActive);
        emit Activity(account, bytes32(0), 0, UtilityCodes.RemoveThenInactive);
        emit Activity(account, bytes32(0), 0, Codes.EnableThenActive);
        emit Activity(account, bytes32(0), 0, Codes.DisableThenInactive);
        emit Activity(account, bytes32(0), 0, Codes.AuthorizeThenActive);
        emit Activity(account, bytes32(0), 0, Codes.RevokeThenInactive);
        emit Activity(account, bytes32(0), 0, Codes.AppointThenActive);
        emit Activity(account, bytes32(0), 0, Codes.DismissThenInactive);
        emit Activity(account, bytes32(0), 0, Codes.AllowThenActive);
        emit Activity(account, bytes32(0), 0, Codes.DenyThenInactive);
        emit Activity(account, bytes32(0), 1, Actions.Swap | (Actions.Borrow << 32) |
            (Effects.Spend << 64) | (Effects.Receive << 96) |
            (Effects.Lock << 128) | (UtilityEffects.Unlock << 160) |
            (States.Active << 192) | (UtilityStates.Inactive << 224));
    }
}
