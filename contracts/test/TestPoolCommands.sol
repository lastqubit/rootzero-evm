// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

import {Host, AssetAmount} from "../Core.sol";
import {AddPool, RemovePool} from "../Endpoints.sol";

contract TestPoolCommands is Host, AddPool, RemovePool {
    uint public calls;
    uint public rejectAt;
    error HookRejected();
    event PoolAdded(bytes32 a, uint aAmount, bytes32 b, uint bAmount);
    event PoolRemoved(bytes32 a, bytes32 b);

    constructor(uint commander) Host(commander, "TestPoolCommands", address(0)) {}

    function getAdminAccount() external view returns (bytes32) { return admin; }
    function failAt(uint callNumber) external { rejectAt = callNumber; }

    function addPool(AssetAmount memory a, AssetAmount memory b) internal override {
        if (++calls == rejectAt) revert HookRejected();
        emit PoolAdded(a.asset, a.amount, b.asset, b.amount);
    }

    function removePool(bytes32 a, bytes32 b) internal override {
        if (++calls == rejectAt) revert HookRejected();
        emit PoolRemoved(a, b);
    }
}
