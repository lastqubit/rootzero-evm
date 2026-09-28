// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

import {ECDSA} from "../utils/ECDSA.sol";

contract TestECDSA {
    using ECDSA for bytes32;

    function testToEthSignedMessageHash(bytes32 hash) external pure returns (bytes32) {
        return hash.toEthSignedMessageHash();
    }

    function testTryRecoverCalldata(bytes32 hash, bytes calldata signature) external pure returns (address) {
        return hash.tryRecoverCalldata(signature);
    }
}

