// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

import {Encoder} from "../codec/Encoder.sol";
import {Blocks} from "../codec/Blocks.sol";
import {Cursors} from "../utils/Cursors.sol";

contract TestCodecAdditions {
    function fixedBlock(uint kind, bytes32[5] calldata fields) external pure returns (bytes memory value, bytes32 padding) {
        if (kind == 0) value = Encoder.createAccount(fields[0]);
        else if (kind == 1) value = Encoder.createAsset(fields[0]);
        else if (kind == 2) value = Encoder.createNode(uint(fields[0]));
        else if (kind == 3) value = Encoder.createStatus(uint(fields[0]));
        else if (kind == 4) value = Encoder.createLimits(uint(fields[0]));
        else if (kind == 5) value = Encoder.createAssetAmount(fields[0], uint(fields[1]));
        else if (kind == 6) value = Encoder.createAssetLiability(fields[0], fields[1]);
        else if (kind == 7) value = Encoder.createAccountAsset(fields[0], fields[1]);
        else if (kind == 8) value = Encoder.createHostAsset(uint(fields[0]), fields[1]);
        // Index 9 retains the historical fixed Bootstrap layout for this corpus.
        else if (kind == 9) value = abi.encodePacked(bytes4(keccak256("#bootstrap")), uint32(96), fields[0], fields[1], fields[2]);
        else if (kind == 10) value = Encoder.createAllocation(uint(fields[0]), fields[1], uint(fields[2]));
        else if (kind == 11) value = Encoder.createAllowance(uint(fields[0]), fields[1], uint(fields[2]));
        else if (kind == 12) value = Encoder.createCustody(uint(fields[0]), fields[1], uint(fields[2]));
        else if (kind == 13) value = Encoder.createAccountAmount(fields[0], fields[1], uint(fields[2]));
        else if (kind == 14) value = Encoder.createHostAmount(uint(fields[0]), fields[1], uint(fields[2]));
        else if (kind == 15) value = Encoder.createHostAccountAsset(uint(fields[0]), fields[1], fields[2]);
        else if (kind == 16) value = Encoder.createQuote(fields[0], uint(fields[1]), fields[2], uint(fields[3]));
        else if (kind == 17) value = Encoder.createTransaction(fields[0], fields[1], fields[2], uint(fields[3]));
        else if (kind == 18) value = Encoder.createHostAccountAmount(uint(fields[0]), fields[1], fields[2], uint(fields[3]));
        else if (kind == 19) value = Encoder.createPosition(fields[0], uint(fields[1]), fields[2], uint(fields[3]), fields[4]);
        else revert();
        assembly ("memory-safe") { padding := mload(add(add(value, 32), mload(value))) }
    }

    function payloadBlock(uint kind, bytes4 key, bytes calldata data, bool memorySource)
        external pure returns (bytes memory value, bytes32 padding)
    {
        uint cur = Cursors.wrap(data) | (uint(0xabcdef) << 128);
        if (memorySource) {
            bytes memory source = data;
            if (kind == 0) value = Encoder.createBlock(key, source);
            else if (kind == 1) value = Encoder.createList(source);
            else if (kind == 2) value = Encoder.createBytes(source);
            else value = Encoder.createString(source);
        } else {
            if (kind == 0) value = Encoder.createBlock(key, cur);
            else if (kind == 1) value = Encoder.createList(cur);
            else if (kind == 2) value = Encoder.createBytes(cur);
            else value = Encoder.createString(cur);
        }
        assembly ("memory-safe") { padding := mload(add(add(value, 32), mload(value))) }
    }

    function oversized(bool memorySource) external pure returns (bytes memory) {
        if (memorySource) {
            bytes memory data = new bytes(0);
            assembly ("memory-safe") { mstore(data, 0xffffffff) }
            return Encoder.createBlock(bytes4(0), data);
        }
        return Encoder.createBlock(bytes4(0), uint(type(uint32).max) << 32);
    }

    function unpack(uint kind, bytes calldata data, uint size)
        external pure returns (bytes32[4] memory fields, uint consumed, uint remaining, uint metadata)
    {
        uint cur = Cursors.wrap(data[:size]) | (uint(0xabcdef) << 128);
        uint host; uint amount;
        if (kind == 0) {
            (amount, cur) = Blocks.unpackStatus(cur);
            fields[0] = bytes32(amount);
        } else if (kind == 1) {
            (host, fields[1], amount, cur) = Blocks.unpackHostAmount(cur);
            fields[0] = bytes32(host); fields[2] = bytes32(amount);
        } else {
            (host, fields[1], fields[2], amount, cur) = Blocks.unpackHostAccountAmount(cur);
            fields[0] = bytes32(host); fields[3] = bytes32(amount);
        }
        consumed = uint32(cur) - Cursors.base(data);
        remaining = Blocks.length(cur);
        metadata = cur >> 128;
    }

    function chain(bytes calldata data) external pure returns (uint code, uint host, bytes32 account, bytes32 asset, uint amount, uint remaining) {
        uint cur = Cursors.wrap(data);
        (code, cur) = Blocks.unpackStatus(cur);
        (host, asset, amount, cur) = Blocks.unpackHostAmount(cur);
        (host, account, asset, amount, cur) = Blocks.unpackHostAccountAmount(cur);
        remaining = Blocks.length(cur);
    }

    function expectAt(bytes calldata data, uint offset, uint width, bytes32 value) external pure {
        expectAbs(Cursors.base(data) + offset, width, value);
    }

    function expectAbs(uint abs, uint width, bytes32 value) public pure {
        if (width == 1) Blocks.expect1(abs, bytes1(value));
        else if (width == 2) Blocks.expect2(abs, bytes2(value));
        else if (width == 4) Blocks.expect4(abs, bytes4(value));
        else if (width == 8) Blocks.expect8(abs, bytes8(value));
        else if (width == 16) Blocks.expect16(abs, bytes16(value));
        else if (width == 32) Blocks.expect32(abs, bytes32(value));
        else revert();
    }
}
