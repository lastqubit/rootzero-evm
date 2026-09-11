// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

import {ActionAnnot} from "../Core.sol";
import {ActionEvent} from "../Events.sol";

contract TestActionEvent is ActionAnnot, ActionEvent {
    function emitAction(bytes32 account, uint32 value) external {
        emit Action(account, value);
    }
}
