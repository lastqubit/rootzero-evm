// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;
import {Blocks} from "../codec/Blocks.sol";

contract TestCursorConversions {
    function checkedString(uint cur) external pure returns (bytes calldata data, uint offset, uint allocated, uint afterCur) {
        uint beforeMemory;
        assembly ("memory-safe") { beforeMemory := mload(0x40) }
        string calldata text = Blocks.toStringChecked(cur);
        data = bytes(text); // Preserve arbitrary bytes without ABI string decoding.
        assembly ("memory-safe") {
            offset := text.offset
            allocated := sub(mload(0x40), beforeMemory)
        }
        afterCur = cur;
    }

    function checked(uint cur) external pure returns (bytes calldata data, uint offset, uint allocated, uint afterCur) {
        uint beforeMemory;
        assembly ("memory-safe") { beforeMemory := mload(0x40) }
        data = Blocks.toBytesChecked(cur);
        assembly ("memory-safe") {
            offset := data.offset
            allocated := sub(mload(0x40), beforeMemory)
        }
        afterCur = cur;
    }

    function inspect(bytes calldata source, uint start, uint end, uint skip, uint metadata)
        external pure returns (bytes calldata data, bytes calldata textBytes, uint offset, uint allocated, uint original, uint afterCur)
    {
        require(start <= end && end <= source.length);
        uint base;
        assembly ("memory-safe") { base := source.offset }
        uint cur = (base + start) | ((base + end) << 32) | (metadata & ~uint(type(uint64).max));
        cur = Blocks.advance(cur, skip);
        original = cur;
        uint beforeMemory;
        assembly ("memory-safe") { beforeMemory := mload(0x40) }
        data = Blocks.toBytes(cur);
        string calldata text = Blocks.toString(cur);
        textBytes = bytes(text);
        assembly ("memory-safe") {
            allocated := sub(mload(0x40), beforeMemory)
            offset := sub(data.offset, base)
            if iszero(eq(data.offset, text.offset)) { revert(0, 0) }
        }
        afterCur = cur;
    }

    function unpackText(bytes calldata blockData) external pure returns (string calldata viewText, string memory copiedText) {
        uint cur;
        assembly ("memory-safe") { cur := or(blockData.offset, shl(32, add(blockData.offset, blockData.length))) }
        (uint payload, ) = Blocks.unpackString(cur);
        viewText = Blocks.toString(payload);
        copiedText = Blocks.toString(payload);
    }
}
