// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

import {Blocks} from "../codec/Blocks.sol";
import {Headers} from "../codec/Headers.sol";
import {Keys} from "../codec/Keys.sol";
import {Cursors} from "../utils/Cursors.sol";

abstract contract UnpackCompositionHarness {
    function unpack(uint cur) internal pure virtual returns (uint sum, uint nextCur);

    function measure(bytes calldata source, uint length) external view
        returns (uint used, uint sum, uint finalCur)
    {
        uint cur = Cursors.wrap(source[:length]) | (uint(0xa5) << 128);
        uint initial = gasleft();
        while (uint32(cur) < uint32(cur >> 32)) {
            uint value;
            (value, cur) = unpack(cur);
            unchecked { sum += value; }
        }
        used = initial - gasleft();
        finalCur = cur;
    }
}

contract UnpackAmountDirect is UnpackCompositionHarness {
    function unpack(uint cur) internal pure override returns (uint sum, uint nextCur) {
        (bytes32 asset, uint amount, uint next) = decode(cur);
        nextCur = next;
        unchecked { sum = uint(asset) + uint(amount); }
    }

    function decode(uint cur) private pure returns (bytes32 asset, uint amount, uint nextCur) {
        uint abs = uint32(cur);
        Blocks.expectHeader(abs, Headers.Amount);
        nextCur = Blocks.advance(cur, 72);
        assembly ("memory-safe") {
            asset := calldataload(add(abs, 8))
            amount := calldataload(add(abs, 40))
        }
    }
}

contract UnpackAmountComposed is UnpackCompositionHarness {
    function unpack(uint cur) internal pure override returns (uint sum, uint nextCur) {
        (bytes32 asset, uint amount, uint next) = Blocks.unpackAmount(cur);
        nextCur = next;
        unchecked { sum = uint(asset) + amount; }
    }
}

contract UnpackBalanceDirect is UnpackCompositionHarness {
    function unpack(uint cur) internal pure override returns (uint sum, uint nextCur) {
        (bytes32 asset, uint amount, uint next) = decode(cur);
        nextCur = next;
        unchecked { sum = uint(asset) + uint(amount); }
    }

    function decode(uint cur) private pure returns (bytes32 asset, uint amount, uint nextCur) {
        uint abs = uint32(cur);
        Blocks.expectHeader(abs, Headers.Balance);
        nextCur = Blocks.advance(cur, 72);
        assembly ("memory-safe") {
            asset := calldataload(add(abs, 8))
            amount := calldataload(add(abs, 40))
        }
    }
}

contract UnpackBalanceComposed is UnpackCompositionHarness {
    function unpack(uint cur) internal pure override returns (uint sum, uint nextCur) {
        (bytes32 asset, uint amount, uint next) = unpackBalance(cur);
        nextCur = next;
        unchecked { sum = uint(asset) + amount; }
    }

    function unpackBalance(uint cur) private pure returns (bytes32 asset, uint amount, uint nextCur) {
        bytes32 word;
        (asset, word, nextCur) = Blocks.unpack64(cur, Keys.Balance);
        amount = uint(word);
    }
}

contract UnpackPositionDirect is UnpackCompositionHarness {
    function unpack(uint cur) internal pure override returns (uint sum, uint nextCur) {
        (bytes32 asset, uint amount, bytes32 liability, uint debt, bytes32 counterparty, uint next) = decode(cur);
        nextCur = next;
        unchecked { sum = uint(asset) + uint(amount) + uint(liability) + uint(debt) + uint(counterparty); }
    }

    function decode(uint cur) private pure returns (bytes32 asset, uint amount, bytes32 liability, uint debt, bytes32 counterparty, uint nextCur) {
        uint abs = uint32(cur);
        Blocks.expectHeader(abs, Headers.Position);
        nextCur = Blocks.advance(cur, 168);
        assembly ("memory-safe") {
            asset := calldataload(add(abs, 8))
            amount := calldataload(add(abs, 40))
            liability := calldataload(add(abs, 72))
            debt := calldataload(add(abs, 104))
            counterparty := calldataload(add(abs, 136))
        }
    }
}

contract UnpackPositionComposed is UnpackCompositionHarness {
    function unpack(uint cur) internal pure override returns (uint sum, uint nextCur) {
        (bytes32 asset, uint amount, bytes32 liability, uint debt, bytes32 counterparty, uint next) = Blocks.unpackPosition(cur);
        nextCur = next;
        unchecked { sum = uint(asset) + amount + uint(liability) + debt + uint(counterparty); }
    }
}

contract UnpackBalanceCurrent is UnpackCompositionHarness {
    function unpack(uint cur) internal pure override returns (uint sum, uint nextCur) {
        (bytes32 asset, uint amount, uint next) = Blocks.unpackBalance(cur);
        nextCur = next;
        unchecked { sum = uint(asset) + amount; }
    }
}
