// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

import {Validator} from "../core/Validator.sol";

contract TestValidator is Validator {
    function testVerify(bytes32 hash, uint192 nonce, bytes calldata proof) external returns (address) {
        return verify(hash, nonce, proof);
    }
}

