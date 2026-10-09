// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

import {TestPoolCommands} from "./TestPoolCommands.sol";
import {UpdatePool, UpdatePoolHook} from "../Endpoints.sol";
import {AssetAmount} from "../core/Types.sol";
import {Accounts} from "../utils/Accounts.sol";

contract TestUpdatePool is TestPoolCommands, UpdatePool {
    mapping(bytes32 => mapping(bytes32 => bool)) public exists;
    mapping(bytes32 => mapping(bytes32 => uint[2])) public reserves;
    uint public updates;
    error MissingPool();
    event PoolUpdated(bytes32 a, uint aAmount, bytes32 b, uint bAmount);

    constructor(address guardian) TestPoolCommands(0) {
        appointGuardian(Accounts.toUser(guardian));
    }

    function seed(bytes32 a, bytes32 b) external { exists[a][b] = true; }
    function dismissTestGuardian(address guardian) external { dismissGuardian(Accounts.toUser(guardian)); }

    function updatePool(AssetAmount memory a, AssetAmount memory b) internal override {
        if (!exists[a.asset][b.asset]) revert MissingPool();
        if (++updates == rejectAt) revert HookRejected();
        reserves[a.asset][b.asset] = [a.amount, b.amount];
        emit PoolUpdated(a.asset, a.amount, b.asset, b.amount);
    }
}
