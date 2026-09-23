// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

import { Accounts } from "../utils/Accounts.sol";
import { Assets } from "../utils/Assets.sol";
import {InvalidAsset} from "../utils/Errors.sol";
import { GetBalance } from "../queries/Balance.sol";
import {Runtime} from "../core/Runtime.sol";

contract TestErc20BalanceToken {
    mapping(address => uint) internal balances;

    function mint(address account, uint amount) external {
        balances[account] += amount;
    }

    function balanceOf(address account) external view returns (uint) {
        return balances[account];
    }
}

contract TestBalancesQuery is GetBalance {
    TestErc20BalanceToken public immutable token = new TestErc20BalanceToken();
    bytes32 public immutable tokenAsset = Assets.toErc20(address(token));

    constructor() Runtime(0) {}

    function mint(address account, uint amount) external {
        token.mint(account, amount);
    }

    function chainAssetId() external view returns (bytes32) {
        return chainAsset;
    }

    receive() external payable {}

    function getBalance(bytes32 account, bytes32 asset) internal view override returns (uint amount) {
        address accountAddr = Accounts.addr(account);
        if (asset == chainAsset) return accountAddr.balance;
        if (asset == tokenAsset) return token.balanceOf(accountAddr);
        revert InvalidAsset();
    }
}
