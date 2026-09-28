// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;
import {LegacyBlocks} from "./LegacyBlocks.sol";
import {PreviousContextCreator} from "./PreviousContextCreator.sol";
import {ReservedBlockEncoder} from "./ReservedBlockEncoder.sol";
import {Encoder} from "../codec/Encoder.sol";

import {Blocks} from "../codec/Blocks.sol";
import {Cursors} from "../utils/Cursors.sol";
import {Keys} from "../codec/Keys.sol";

abstract contract BlockWriterHarness {
    function reservedSize(uint stateSize, uint inputSize) internal pure virtual returns (uint) {
        return 56 + stateSize + inputSize + 24;
    }
    function write(bytes memory dst, uint i, bytes32 account, bytes calldata state, bytes calldata input, uint stateCur, uint inputCur)
        internal pure virtual;
    function writeMemory(bytes memory dst, uint i, bytes32 account, bytes memory state, bytes memory input)
        internal pure virtual;

    function measureWrite(bytes32 account, bytes calldata state, bytes calldata input, uint count, uint offset, bool memorySource)
        external view returns (uint used, uint allocated, bytes memory output)
    {
        uint stateCur = Cursors.wrap(state);
        uint inputCur = Cursors.wrap(input);
        bytes memory stateMemory;
        bytes memory inputMemory;
        if (memorySource) { stateMemory = state; inputMemory = input; }
        // Prefix and suffix guards surround the complete block plus allowed scratch.
        output = new bytes(offset + reservedSize(state.length, input.length) + 32);
        for (uint j; j < output.length; ++j) output[j] = 0xef;
        uint beforeMemory;
        assembly ("memory-safe") { beforeMemory := mload(0x40) }
        uint initial = gasleft();
        for (uint j; j < count; ++j) {
            if (memorySource) writeMemory(output, offset, account, stateMemory, inputMemory);
            else write(output, offset, account, state, input, stateCur, inputCur);
        }
        used = initial - gasleft();
        assembly ("memory-safe") { allocated := sub(mload(0x40), beforeMemory) }
        if (memorySource) {
            require(keccak256(stateMemory) == keccak256(state));
            require(keccak256(inputMemory) == keccak256(input));
        }
    }

}

abstract contract BlockEncoderHarness {
    function encode(bytes32 account, bytes calldata state, bytes calldata input, uint stateCur, uint inputCur)
        internal pure virtual returns (bytes memory);
    function encodeMemory(bytes32 account, bytes memory state, bytes memory input)
        internal pure virtual returns (bytes memory);

    function inspect(bytes32 account, bytes calldata source, uint start, uint split, uint end, uint metadata, bool memorySource)
        external pure returns (bytes memory output, uint stateCur, uint inputCur)
    {
        require(start <= split && split <= end && end <= source.length);
        bytes calldata state = source[start:split];
        bytes calldata input = source[split:end];
        uint flags = metadata & ~uint(type(uint64).max);
        stateCur = Cursors.wrap(state) | flags;
        inputCur = Cursors.wrap(input) | flags;
        output = memorySource ? encodeMemory(account, state, input) : encode(account, state, input, stateCur, inputCur);
    }

    function measure(bytes32 account, bytes calldata state, bytes calldata input, uint count, bool memorySource)
        external view returns (uint used, uint allocated, bytes memory output)
    {
        uint stateCur = Cursors.wrap(state);
        uint inputCur = Cursors.wrap(input);
        // Deliberate setup outside the timer for the memory-to-memory comparison.
        bytes memory stateMemory;
        bytes memory inputMemory;
        if (memorySource) { stateMemory = state; inputMemory = input; }
        uint beforeMemory;
        assembly ("memory-safe") { beforeMemory := mload(0x40) }
        uint initial = gasleft();
        for (uint i; i < count; ++i) {
            output = memorySource ? encodeMemory(account, stateMemory, inputMemory) : encode(account, state, input, stateCur, inputCur);
        }
        used = initial - gasleft();
        assembly ("memory-safe") { allocated := sub(mload(0x40), beforeMemory) }
    }
}
contract TestBlockWriter is BlockWriterHarness {
    function write(bytes memory dst, uint i, bytes32 account, bytes calldata, bytes calldata, uint stateCur, uint inputCur)
        internal pure override
    { ReservedBlockEncoder.writeContextWrap(dst, i, account, stateCur, inputCur); }
    function writeMemory(bytes memory dst, uint i, bytes32 account, bytes memory state, bytes memory input)
        internal pure override
    { ReservedBlockEncoder.writeContextWrap(dst, i, account, state, input); }
}
contract TestBlockEncoder is BlockEncoderHarness {
    function encode(bytes32 account, bytes calldata, bytes calldata, uint stateCur, uint inputCur)
        internal pure override returns (bytes memory)
    { return Encoder.createContext(account, stateCur, inputCur); }
    function encodeMemory(bytes32 account, bytes memory state, bytes memory input)
        internal pure override returns (bytes memory)
    { return Encoder.createContext(account, state, input); }

    function reencode(bytes calldata context) external pure returns (bytes memory output) {
        (bytes32 account, uint stateCur, uint inputCur, ) = Blocks.unpackContext(Cursors.wrap(context));
        return Encoder.createContext(account, stateCur, inputCur);
    }
}
contract TestBlockWriterPrevious is BlockWriterHarness {
    function write(bytes memory dst, uint i, bytes32 account, bytes calldata state, bytes calldata input, uint, uint)
        internal pure override
    { LegacyBlocks.copyContext(dst, i, account, state, input); }
    function writeMemory(bytes memory dst, uint i, bytes32 account, bytes memory state, bytes memory input)
        internal pure override
    { LegacyBlocks.writeContext(dst, i, account, state, input); }
}
contract TestBlockEncoderPrevious is BlockEncoderHarness {
    function encode(bytes32 account, bytes calldata state, bytes calldata input, uint, uint)
        internal pure override returns (bytes memory)
    { return LegacyBlocks.createContextCopy(account, state, input); }
    function encodeMemory(bytes32 account, bytes memory state, bytes memory input)
        internal pure override returns (bytes memory)
    { return LegacyBlocks.createContext(account, state, input); }
}

// Historical complete-child creator comparison, not a production API.
contract TestBlockEncoderCopy is BlockEncoderHarness {
    function encode(bytes32 account, bytes calldata, bytes calldata, uint stateCur, uint inputCur)
        internal pure override returns (bytes memory)
    { return PreviousContextCreator.createContext(account, stateCur, inputCur); }
    function encodeMemory(bytes32 account, bytes memory state, bytes memory input)
        internal pure override returns (bytes memory)
    { return PreviousContextCreator.createContext(account, state, input); }

    function reencode(bytes calldata source) external pure returns (bytes memory) {
        (uint abs, uint cur, ) = Blocks.enter(Cursors.wrap(source), Keys.Context, 32);
        bytes32 account = Blocks.read32(abs);
        uint stateCur;
        uint inputCur;
        (stateCur, cur) = Blocks.take(cur, Keys.Bytes);
        (inputCur, cur) = Blocks.take(cur, Keys.Bytes);
        require(uint32(cur) == uint32(cur >> 32));
        return PreviousContextCreator.createContext(account, stateCur, inputCur);
    }
}

contract TestBlockWriterCopy is BlockWriterHarness {
    function reservedSize(uint stateSize, uint inputSize) internal pure override returns (uint) {
        return 40 + stateSize + inputSize;
    }
    function write(bytes memory dst, uint i, bytes32 account, bytes calldata, bytes calldata, uint stateCur, uint inputCur)
        internal pure override
    { ReservedBlockEncoder.writeContext(dst, i, account, stateCur, inputCur); }
    function writeMemory(bytes memory dst, uint i, bytes32 account, bytes memory state, bytes memory input)
        internal pure override
    { ReservedBlockEncoder.writeContext(dst, i, account, state, input); }
}

// Keep allocator checks separate from the timed consumers so they do not affect inlining.
contract TestBlockEncoderMemory {
    function inspect(bytes32 account, bytes calldata state, bytes calldata input, bool memorySource)
        external pure returns (bytes memory first, bytes memory second, bool cleanPadding)
    {
        bytes memory stateMemory = state;
        bytes memory inputMemory = input;
        uint size = 56 + state.length + input.length;
        // Temporary free memory need not be zero when an allocator receives it.
        assembly ("memory-safe") {
            let p := mload(0x40)
            for { let end := add(p, add(size, 96)) } lt(p, end) { p := add(p, 32) } {
                mstore(p, not(0))
            }
        }
        first = memorySource
            ? Encoder.createContext(account, stateMemory, inputMemory)
            : Encoder.createContext(account, Cursors.wrap(state), Cursors.wrap(input));
        cleanPadding = true;
        assembly ("memory-safe") {
            let remainder := and(mload(first), 31)
            if remainder {
                let last := add(add(first, 32), and(mload(first), not(31)))
                let mask := sub(shl(mul(sub(32, remainder), 8), 1), 1)
                cleanPadding := iszero(and(mload(last), mask))
            }
        }
        // A following allocation must neither corrupt the first output nor its sources.
        second = Encoder.createContext(account, inputMemory, stateMemory);
        require(keccak256(stateMemory) == keccak256(state));
        require(keccak256(inputMemory) == keccak256(input));
    }

    function oversized() external pure returns (bytes memory) {
        bytes memory state = new bytes(0);
        bytes memory input = new bytes(0);
        // Synthetic size: rejection must happen before any source payload is read.
        assembly ("memory-safe") { mstore(state, 0xffffffff) }
        return Encoder.createContext(bytes32(0), state, input);
    }
}

// A different schema built solely from generic primitives, with mixed child handling.
contract TestBlockEncoderComposition {
    function encode(bytes4 key, bytes32 word, bytes calldata payload, bytes calldata child, bool memorySource)
        external pure returns (bytes memory output, uint written)
    {
        (uint block, uint nextCur) = Blocks.take(Cursors.wrap(child));
        require(uint32(nextCur) == uint32(nextCur >> 32));
        bytes memory payloadMemory;
        bytes memory childMemory;
        if (memorySource) { payloadMemory = payload; childMemory = child; }
        uint size = 48 + payload.length + child.length;
        output = Encoder.allocate(size);
        uint abs = Encoder.pos(output, 0);
        uint start = abs;
        abs = Encoder.writeHeader(abs, key, size - 8);
        abs = Encoder.write32(abs, word);
        if (memorySource) {
            abs = Encoder.wrap(abs, Keys.Bytes, payloadMemory);
            abs = Encoder.copy(abs, childMemory);
        } else {
            abs = Encoder.wrap(abs, Keys.Bytes, Cursors.wrap(payload));
            abs = Encoder.copy(abs, block);
        }
        written = abs - start;
    }
}

contract TestBlockEncoderNextOffsets {
    function chain(bytes32 account, bytes calldata state, bytes calldata input, bool wrap, bool memorySource)
        external pure returns (bytes memory output, uint nextI)
    {
        bytes memory stateMemory;
        bytes memory inputMemory;
        if (memorySource) { stateMemory = state; inputMemory = input; }
        uint size = (wrap ? 56 : 40) + state.length + input.length;
        output = new bytes(3 + 2 * size + 24 + 32);
        for (uint j; j < output.length; ++j) output[j] = 0xef;
        nextI = 3;
        for (uint j; j < 2; ++j) {
            if (memorySource) {
                nextI = wrap ? ReservedBlockEncoder.writeContextWrap(output, nextI, account, stateMemory, inputMemory)
                    : ReservedBlockEncoder.writeContext(output, nextI, account, stateMemory, inputMemory);
            } else {
                nextI = wrap ? ReservedBlockEncoder.writeContextWrap(output, nextI, account, Cursors.wrap(state), Cursors.wrap(input))
                    : ReservedBlockEncoder.writeContext(output, nextI, account, Cursors.wrap(state), Cursors.wrap(input));
            }
        }
    }
}
