// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

import {Host, AssetAmount} from "../Core.sol";
import {AddPool, RemovePool} from "../Endpoints.sol";

contract TestPoolCommands is Host, AddPool, RemovePool {
    uint public calls;
    uint public rejectAt;
    error HookRejected();
    event PoolAdded(bytes32 first, uint firstAmount, bytes32 second, uint secondAmount);
    event PoolRemoved(bytes32 first, bytes32 second);

    constructor(uint commander) Host(commander) {}

    function getAdminAccount() external view returns (bytes32) { return admin; }
    function failAt(uint callNumber) external { rejectAt = callNumber; }

    function addPool(AssetAmount memory first, AssetAmount memory second) internal override {
        if (++calls == rejectAt) revert HookRejected();
        emit PoolAdded(first.asset, first.amount, second.asset, second.amount);
    }

    function removePool(bytes32 first, bytes32 second) internal override {
        if (++calls == rejectAt) revert HookRejected();
        emit PoolRemoved(first, second);
    }
}
