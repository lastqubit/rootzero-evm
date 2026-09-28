// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

contract TestRejectEther {
    receive() external payable {
        revert("NO_ETH");
    }
}

