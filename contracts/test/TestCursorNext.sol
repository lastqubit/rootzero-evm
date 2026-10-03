// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;
import {RangeCursorBlocks} from "./RangeCursorBlocks.sol";
import {Blocks, Cursors} from "../Codec.sol";
import {BALANCE_HEADER} from "../codec/Specs.sol";
import {STEP_KEY, INPUT_KEY} from "../codec/Keys.sol";
import {INVALID_BLOCK, OUT_OF_BOUNDS} from "../utils/Errors.sol";

/// @dev Direct alternatives isolate the effect of packing intermediate ranges.
library CursorNextCandidates {
    function balanceComposed(uint cur) internal pure returns (bytes32 asset, uint amount, uint nextCur) {
        uint blockCur;
        (asset, amount, blockCur) = RangeCursorBlocks.unpackBalance(cur);
        nextCur = advanceTo(cur, uint32(blockCur >> 32));
    }
    function stepComposed(uint cur) internal pure returns (uint cmd, uint value, uint inputCur, uint nextCur) {
        (cmd, value, inputCur) = RangeCursorBlocks.unpackStep(cur);
        nextCur = advanceTo(cur, uint32(inputCur >> 32));
    }
    function advanceTo(uint cur, uint endAbs) private pure returns (uint nextCur) {
        assembly ("memory-safe") { nextCur := or(and(cur, not(0xffffffff)), endAbs) }
    }

    function balance(uint cur) internal pure returns (bytes32 asset, uint amount, uint nextCur) {
        assembly ("memory-safe") {
            let abs := and(cur, 0xffffffff)
            if iszero(eq(shr(192, calldataload(abs)), BALANCE_HEADER)) {
                mstore(0, INVALID_BLOCK) revert(28, 4)
            }
            let endAbs := add(abs, 72)
            if gt(endAbs, and(shr(32, cur), 0xffffffff)) {
                mstore(0, OUT_OF_BOUNDS) revert(28, 4)
            }
            asset := calldataload(add(abs, 8))
            amount := calldataload(add(abs, 40))
            nextCur := or(and(cur, not(0xffffffff)), endAbs)
        }
    }
    function step(uint cur) internal pure returns (uint cmd, uint value, uint inputCur, uint nextCur) {
        assembly ("memory-safe") {
            let abs := and(cur, 0xffffffff)
            let header := calldataload(abs)
            if iszero(eq(shr(224, header), STEP_KEY)) {
                mstore(0, INVALID_BLOCK) revert(28, 4)
            }
            let endAbs := add(add(abs, 8), and(shr(192, header), 0xffffffff))
            if gt(endAbs, and(shr(32, cur), 0xffffffff)) {
                mstore(0, OUT_OF_BOUNDS) revert(28, 4)
            }
            let bodyAbs := add(abs, 80)
            if or(lt(endAbs, bodyAbs), iszero(eq(shr(192, calldataload(add(abs, 72))), or(shl(32, INPUT_KEY), sub(endAbs, bodyAbs))))) {
                mstore(0, INVALID_BLOCK) revert(28, 4)
            }
            cmd := calldataload(add(abs, 8))
            value := calldataload(add(abs, 40))
            inputCur := or(bodyAbs, shl(32, endAbs))
            nextCur := or(and(cur, not(0xffffffff)), endAbs)
        }
    }
}

abstract contract CursorNextBalanceHarness {
    function decode(uint cur) internal pure virtual returns (bytes32 asset, uint amount, uint nextCur);
    function inspect(bytes calldata source, uint length, uint offset, uint metadata)
        external pure returns (bytes32 asset, uint amount, uint nextCur, uint originalCur, uint baseAbs)
    {
        require(length <= source.length);
        baseAbs = Cursors.base(source);
        originalCur = (baseAbs + offset) | ((baseAbs + length) << 32) | (metadata & ~uint(type(uint64).max));
        (asset, amount, nextCur) = decode(originalCur);
    }
    function onlyValues(bytes calldata source) external pure returns (bytes32 asset, uint amount) {
        (asset, amount,) = decode(Cursors.wrap(source));
    }
    function measure(bytes calldata source) external view virtual returns (uint used, uint sum, uint cur) {
        cur = Cursors.wrap(source) | (uint(0xa5) << 64);
        uint beforeGas = gasleft();
        while (uint32(cur) < uint32(cur >> 32)) {
            bytes32 asset; uint amount;
            (asset, amount, cur) = decode(cur);
            unchecked { sum += uint(asset) + amount; }
        }
        used = beforeGas - gasleft();
    }
    function measureDiscard(bytes calldata source) external view virtual returns (uint used, uint sum, uint cur) {
        cur = Cursors.wrap(source) | (uint(0xa5) << 64);
        uint beforeGas = gasleft();
        while (uint32(cur) < uint32(cur >> 32)) {
            (bytes32 asset, uint amount,) = decode(cur);
            unchecked { sum += uint(asset) + amount; cur += 72; }
        }
        used = beforeGas - gasleft();
    }
}
contract CursorNextBalanceSelected is CursorNextBalanceHarness {
    function measure(bytes calldata source) external view override returns (uint used, uint sum, uint cur) {
        cur = Cursors.wrap(source) | (uint(0xa5) << 64);
        uint beforeGas = gasleft();
        while (uint32(cur) < uint32(cur >> 32)) {
            (bytes32 asset, uint amount, uint blockCur) = RangeCursorBlocks.unpackBalance(cur);
            unchecked { sum += uint(asset) + amount; }
            cur = (cur & ~uint(type(uint32).max)) | uint32(blockCur >> 32);
        }
        used = beforeGas - gasleft();
    }
    function measureDiscard(bytes calldata source) external view override returns (uint used, uint sum, uint cur) {
        cur = Cursors.wrap(source) | (uint(0xa5) << 64);
        uint beforeGas = gasleft();
        while (uint32(cur) < uint32(cur >> 32)) {
            (bytes32 asset, uint amount,) = RangeCursorBlocks.unpackBalance(cur);
            unchecked { sum += uint(asset) + amount; cur += 72; }
        }
        used = beforeGas - gasleft();
    }

    function decode(uint cur) internal pure override returns (bytes32 asset, uint amount, uint nextCur) {
        uint blockCur;
        (asset, amount, blockCur) = RangeCursorBlocks.unpackBalance(cur);
        nextCur = (cur & ~uint(type(uint32).max)) | uint32(blockCur >> 32);
    }
}
contract CursorNextBalanceCurrent is CursorNextBalanceHarness {
    function decode(uint cur) internal pure override returns (bytes32, uint, uint) {
        return Blocks.unpackBalance(cur);
    }
}
contract CursorNextBalanceDirect is CursorNextBalanceHarness {
    function decode(uint cur) internal pure override returns (bytes32, uint, uint) {
        return CursorNextCandidates.balance(cur);
    }
}

abstract contract CursorNextStepHarness {
    function decode(uint cur) internal pure virtual returns (uint cmd, uint value, uint inputCur, uint nextCur);
    function inspect(bytes calldata source, uint length, uint offset, uint metadata)
        external pure returns (uint cmd, uint value, uint inputCur, uint nextCur, uint originalCur, uint baseAbs, bytes memory data)
    {
        require(length <= source.length);
        baseAbs = Cursors.base(source);
        originalCur = (baseAbs + offset) | ((baseAbs + length) << 32) | (metadata & ~uint(type(uint64).max));
        (cmd, value, inputCur, nextCur) = decode(originalCur);
        data = Cursors.toBytes(inputCur);
    }
    function onlyValues(bytes calldata source) external pure returns (uint cmd, uint value) {
        (cmd, value,,) = decode(Cursors.wrap(source));
    }
    function measure(bytes calldata source) external view virtual returns (uint used, uint sum, uint cur) {
        cur = Cursors.wrap(source) | (uint(0xa5) << 64);
        uint beforeGas = gasleft();
        while (uint32(cur) < uint32(cur >> 32)) {
            uint cmd; uint value; uint inputCur;
            (cmd, value, inputCur, cur) = decode(cur);
            unchecked { sum += cmd + value + uint32(inputCur >> 32) - uint32(inputCur); }
        }
        used = beforeGas - gasleft();
    }
    function measureData(bytes calldata source) external view virtual returns (uint used, uint sum, uint cur) {
        cur = Cursors.wrap(source) | (uint(0xa5) << 64);
        uint beforeGas = gasleft();
        while (uint32(cur) < uint32(cur >> 32)) {
            uint cmd; uint value; uint inputCur;
            (cmd, value, inputCur, cur) = decode(cur);
            unchecked { sum += cmd + value + uint(keccak256(Cursors.toBytes(inputCur))); }
        }
        used = beforeGas - gasleft();
    }
}
contract CursorNextStepSelected is CursorNextStepHarness {
    function measure(bytes calldata source) external view override returns (uint used, uint sum, uint cur) {
        cur = Cursors.wrap(source) | (uint(0xa5) << 64);
        uint beforeGas = gasleft();
        while (uint32(cur) < uint32(cur >> 32)) {
            (uint cmd, uint value, uint inputCur) = RangeCursorBlocks.unpackStep(cur);
            unchecked { sum += cmd + value + uint32(inputCur >> 32) - uint32(inputCur); }
            cur = (cur & ~uint(type(uint32).max)) | uint32(inputCur >> 32);
        }
        used = beforeGas - gasleft();
    }
    function measureData(bytes calldata source) external view override returns (uint used, uint sum, uint cur) {
        cur = Cursors.wrap(source) | (uint(0xa5) << 64);
        uint beforeGas = gasleft();
        while (uint32(cur) < uint32(cur >> 32)) {
            (uint cmd, uint value, uint inputCur) = RangeCursorBlocks.unpackStep(cur);
            unchecked { sum += cmd + value + uint(keccak256(Cursors.toBytes(inputCur))); }
            cur = (cur & ~uint(type(uint32).max)) | uint32(inputCur >> 32);
        }
        used = beforeGas - gasleft();
    }

    function decode(uint cur) internal pure override returns (uint cmd, uint value, uint inputCur, uint nextCur) {
        (cmd, value, inputCur) = RangeCursorBlocks.unpackStep(cur);
        nextCur = (cur & ~uint(type(uint32).max)) | uint32(inputCur >> 32);
    }
}
contract CursorNextStepCurrent is CursorNextStepHarness {
    function decode(uint cur) internal pure override returns (uint, uint, uint, uint) {
        return Blocks.unpackStep(cur);
    }
}
contract CursorNextStepDirect is CursorNextStepHarness {
    function decode(uint cur) internal pure override returns (uint, uint, uint, uint) {
        return CursorNextCandidates.step(cur);
    }
}

contract CursorNextBalanceComposed is CursorNextBalanceHarness {
    function decode(uint cur) internal pure override returns (bytes32, uint, uint) {
        return CursorNextCandidates.balanceComposed(cur);
    }
}
contract CursorNextStepComposed is CursorNextStepHarness {
    function decode(uint cur) internal pure override returns (uint, uint, uint, uint) {
        return CursorNextCandidates.stepComposed(cur);
    }
}

// Minimal consumers exclude correctness-entrypoint effects on compiler inlining.
contract CursorNextBalanceLoopSelected {
    function measure(bytes calldata source) external view returns (uint used, uint sum, uint cur) {
        cur = Cursors.wrap(source) | (uint(0xa5) << 64);
        uint beforeGas = gasleft();
        while (uint32(cur) < uint32(cur >> 32)) {
            (bytes32 asset, uint amount, uint blockCur) = RangeCursorBlocks.unpackBalance(cur);
            unchecked { sum += uint(asset) + amount; }
            cur = (cur & ~uint(type(uint32).max)) | uint32(blockCur >> 32);
        }
        used = beforeGas - gasleft();
    }
    function measureDiscard(bytes calldata source) external view returns (uint used, uint sum, uint cur) {
        cur = Cursors.wrap(source) | (uint(0xa5) << 64);
        uint beforeGas = gasleft();
        while (uint32(cur) < uint32(cur >> 32)) {
            (bytes32 asset, uint amount,) = RangeCursorBlocks.unpackBalance(cur);
            unchecked { sum += uint(asset) + amount; cur += 72; }
        }
        used = beforeGas - gasleft();
    }
}
contract CursorNextBalanceLoopCurrent {
    function measure(bytes calldata source) external view returns (uint used, uint sum, uint cur) {
        cur = Cursors.wrap(source) | (uint(0xa5) << 64);
        uint beforeGas = gasleft();
        while (uint32(cur) < uint32(cur >> 32)) {
            bytes32 asset; uint amount;
            (asset, amount, cur) = Blocks.unpackBalance(cur);
            unchecked { sum += uint(asset) + amount; }
        }
        used = beforeGas - gasleft();
    }
    function measureDiscard(bytes calldata source) external view returns (uint used, uint sum, uint cur) {
        cur = Cursors.wrap(source) | (uint(0xa5) << 64);
        uint beforeGas = gasleft();
        while (uint32(cur) < uint32(cur >> 32)) {
            (bytes32 asset, uint amount,) = Blocks.unpackBalance(cur);
            unchecked { sum += uint(asset) + amount; cur += 72; }
        }
        used = beforeGas - gasleft();
    }
}
contract CursorNextStepLoopSelected {
    function measure(bytes calldata source) external view returns (uint used, uint sum, uint cur) {
        cur = Cursors.wrap(source) | (uint(0xa5) << 64);
        uint beforeGas = gasleft();
        while (uint32(cur) < uint32(cur >> 32)) {
            (uint cmd, uint value, uint inputCur) = RangeCursorBlocks.unpackStep(cur);
            unchecked { sum += cmd + value + uint32(inputCur >> 32) - uint32(inputCur); }
            cur = (cur & ~uint(type(uint32).max)) | uint32(inputCur >> 32);
        }
        used = beforeGas - gasleft();
    }
    function measureData(bytes calldata source) external view returns (uint used, uint sum, uint cur) {
        cur = Cursors.wrap(source) | (uint(0xa5) << 64);
        uint beforeGas = gasleft();
        while (uint32(cur) < uint32(cur >> 32)) {
            (uint cmd, uint value, uint inputCur) = RangeCursorBlocks.unpackStep(cur);
            unchecked { sum += cmd + value + uint(keccak256(Cursors.toBytes(inputCur))); }
            cur = (cur & ~uint(type(uint32).max)) | uint32(inputCur >> 32);
        }
        used = beforeGas - gasleft();
    }
}
contract CursorNextStepLoopCurrent {
    function measure(bytes calldata source) external view returns (uint used, uint sum, uint cur) {
        cur = Cursors.wrap(source) | (uint(0xa5) << 64);
        uint beforeGas = gasleft();
        while (uint32(cur) < uint32(cur >> 32)) {
            uint cmd; uint value; uint inputCur;
            (cmd, value, inputCur, cur) = Blocks.unpackStep(cur);
            unchecked { sum += cmd + value + uint32(inputCur >> 32) - uint32(inputCur); }
        }
        used = beforeGas - gasleft();
    }
    function measureData(bytes calldata source) external view returns (uint used, uint sum, uint cur) {
        cur = Cursors.wrap(source) | (uint(0xa5) << 64);
        uint beforeGas = gasleft();
        while (uint32(cur) < uint32(cur >> 32)) {
            uint cmd; uint value; uint inputCur;
            (cmd, value, inputCur, cur) = Blocks.unpackStep(cur);
            unchecked { sum += cmd + value + uint(keccak256(Cursors.toBytes(inputCur))); }
        }
        used = beforeGas - gasleft();
    }
}

contract CursorNextBalanceLoopDirect {
    function measure(bytes calldata source) external view returns (uint used, uint sum, uint cur) {
        cur = Cursors.wrap(source) | (uint(0xa5) << 64);
        uint beforeGas = gasleft();
        while (uint32(cur) < uint32(cur >> 32)) {
            bytes32 asset; uint amount;
            (asset, amount, cur) = CursorNextCandidates.balance(cur);
            unchecked { sum += uint(asset) + amount; }
        }
        used = beforeGas - gasleft();
    }
    function measureDiscard(bytes calldata source) external view returns (uint used, uint sum, uint cur) {
        cur = Cursors.wrap(source) | (uint(0xa5) << 64);
        uint beforeGas = gasleft();
        while (uint32(cur) < uint32(cur >> 32)) {
            (bytes32 asset, uint amount,) = CursorNextCandidates.balance(cur);
            unchecked { sum += uint(asset) + amount; cur += 72; }
        }
        used = beforeGas - gasleft();
    }
}

contract CursorNextStepLoopDirect {
    function measure(bytes calldata source) external view returns (uint used, uint sum, uint cur) {
        cur = Cursors.wrap(source) | (uint(0xa5) << 64);
        uint beforeGas = gasleft();
        while (uint32(cur) < uint32(cur >> 32)) {
            uint cmd; uint value; uint inputCur;
            (cmd, value, inputCur, cur) = CursorNextCandidates.step(cur);
            unchecked { sum += cmd + value + uint32(inputCur >> 32) - uint32(inputCur); }
        }
        used = beforeGas - gasleft();
    }
    function measureData(bytes calldata source) external view returns (uint used, uint sum, uint cur) {
        cur = Cursors.wrap(source) | (uint(0xa5) << 64);
        uint beforeGas = gasleft();
        while (uint32(cur) < uint32(cur >> 32)) {
            uint cmd; uint value; uint inputCur;
            (cmd, value, inputCur, cur) = CursorNextCandidates.step(cur);
            unchecked { sum += cmd + value + uint(keccak256(Cursors.toBytes(inputCur))); }
        }
        used = beforeGas - gasleft();
    }
}
