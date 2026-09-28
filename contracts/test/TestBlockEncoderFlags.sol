// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;
import {PreviousContextCreator} from "./PreviousContextCreator.sol";
import {ReservedBlockEncoder} from "./ReservedBlockEncoder.sol";
import {Encoder as E} from "../codec/Encoder.sol";
import {Keys} from "../codec/Keys.sol";
import {Cursors} from "../utils/Cursors.sol";

/// @dev Benchmark-only candidate. true selects a validated complete BYTES child.
/// Same size, bounds, non-overlap, and scratch preconditions as Encoder.
library FlagBlockEncoder {
    function createContext(bytes32 account, bytes memory state, bool stateBlock, bytes memory input, bool inputBlock) internal pure returns (bytes memory value)  {
        uint stateSize = state.length;
        uint inputSize = input.length;
        uint size = uint(40) + (stateBlock ? 0 : 8) + (inputBlock ? 0 : 8) + stateSize + inputSize;
        value = E.allocate(size);
        uint abs = E.pos(value, 0);
        unchecked {
            abs = E.writeHeader(abs, Keys.Context, size - 8);
            abs = E.write32(abs, account);
            abs = stateBlock ? E.copy(abs, state, stateSize) : E.wrap(abs, Keys.Bytes, state, stateSize);
            if (inputBlock) E.copy(abs, input, inputSize);
            else E.wrap(abs, Keys.Bytes, input, inputSize);
        }
    }
    function writeContext(bytes memory dst, uint offset, bytes32 account, bytes memory state, bool stateBlock, bytes memory input, bool inputBlock) internal pure  {
        uint stateSize = state.length;
        uint inputSize = input.length;
        uint abs = E.pos(dst, offset);
        unchecked {
            abs = E.writeHeader(abs, Keys.Context, 32 + (stateBlock ? 0 : 8) + (inputBlock ? 0 : 8) + stateSize + inputSize);
            abs = E.write32(abs, account);
            abs = stateBlock ? E.copy(abs, state, stateSize) : E.wrap(abs, Keys.Bytes, state, stateSize);
            if (inputBlock) E.copy(abs, input, inputSize);
            else E.wrap(abs, Keys.Bytes, input, inputSize);
        }
    }
    function createContext(bytes32 account, uint state, bool stateBlock, uint input, bool inputBlock) internal pure returns (bytes memory value)  {
        uint stateSize = E.length(state);
        uint inputSize = E.length(input);
        uint size = uint(40) + (stateBlock ? 0 : 8) + (inputBlock ? 0 : 8) + stateSize + inputSize;
        value = E.allocate(size);
        uint abs = E.pos(value, 0);
        unchecked {
            abs = E.writeHeader(abs, Keys.Context, size - 8);
            abs = E.write32(abs, account);
            abs = stateBlock ? E.copy(abs, uint32(state), stateSize) : E.wrap(abs, Keys.Bytes, uint32(state), stateSize);
            if (inputBlock) E.copy(abs, uint32(input), inputSize);
            else E.wrap(abs, Keys.Bytes, uint32(input), inputSize);
        }
    }
    function writeContext(bytes memory dst, uint offset, bytes32 account, uint state, bool stateBlock, uint input, bool inputBlock) internal pure  {
        uint stateSize = E.length(state);
        uint inputSize = E.length(input);
        uint abs = E.pos(dst, offset);
        unchecked {
            abs = E.writeHeader(abs, Keys.Context, 32 + (stateBlock ? 0 : 8) + (inputBlock ? 0 : 8) + stateSize + inputSize);
            abs = E.write32(abs, account);
            abs = stateBlock ? E.copy(abs, uint32(state), stateSize) : E.wrap(abs, Keys.Bytes, uint32(state), stateSize);
            if (inputBlock) E.copy(abs, uint32(input), inputSize);
            else E.wrap(abs, Keys.Bytes, uint32(input), inputSize);
        }
    }
}

/// @dev Identical timed loop for every candidate. Setup/conversion is outside timing.
abstract contract FlagEncoderHarness {
    function flags(bool stateBlock, bool inputBlock) internal pure virtual returns (bool, bool);
    function encode(bytes memory dst, bool writer, bytes32 account, bytes memory state, bool stateBlock, bytes memory input, bool inputBlock) internal pure virtual returns (bytes memory) {
        if (!writer) return FlagBlockEncoder.createContext(account, state, stateBlock, input, inputBlock);
        FlagBlockEncoder.writeContext(dst, 3, account, state, stateBlock, input, inputBlock);
        return dst;
    }
    function encode(bytes memory dst, bool writer, bytes32 account, uint state, bool stateBlock, uint input, bool inputBlock) internal pure virtual returns (bytes memory) {
        if (!writer) return FlagBlockEncoder.createContext(account, state, stateBlock, input, inputBlock);
        FlagBlockEncoder.writeContext(dst, 3, account, state, stateBlock, input, inputBlock);
        return dst;
    }
    function measure(bytes32 account, bytes calldata state, bytes calldata input, bool stateBlock, bool inputBlock, bool memorySource, bool writer, uint count)
        external view returns (uint used, uint allocated, bytes memory output)
    {
        (stateBlock, inputBlock) = flags(stateBlock, inputBlock);
        uint stateCur = Cursors.wrap(state);
        uint inputCur = Cursors.wrap(input);
        bytes memory stateMemory;
        bytes memory inputMemory;
        if (memorySource) { stateMemory = state; inputMemory = input; }
        bytes memory dst;
        if (writer) {
            uint size = 40 + state.length + input.length + (stateBlock ? 0 : 8) + (inputBlock ? 0 : 8);
            dst = new bytes(3 + size + 24 + 32);
            for (uint j; j < dst.length; ++j) dst[j] = 0xef;
        }
        uint initialMemory;
        assembly ("memory-safe") { initialMemory := mload(0x40) }
        uint initialGas = gasleft();
        for (uint j; j < count; ++j) {
            output = memorySource
                ? encode(dst, writer, account, stateMemory, stateBlock, inputMemory, inputBlock)
                : encode(dst, writer, account, stateCur, stateBlock, inputCur, inputBlock);
        }
        used = initialGas - gasleft();
        assembly ("memory-safe") { allocated := sub(mload(0x40), initialMemory) }
        if (memorySource) {
            require(keccak256(stateMemory) == keccak256(state));
            require(keccak256(inputMemory) == keccak256(input));
        }
    }
}
contract TestEncoderFlagsRuntime is FlagEncoderHarness {
    function flags(bool s, bool i) internal pure override returns (bool, bool) { return (s, i); }
}
contract TestEncoderFlagsLiteral0 is FlagEncoderHarness {
    function flags(bool, bool) internal pure override returns (bool, bool) { return (false, false); }
    function encode(bytes memory dst, bool writer, bytes32 account, bytes memory state, bool, bytes memory input, bool) internal pure override returns (bytes memory) {
        if (!writer) return FlagBlockEncoder.createContext(account, state, false, input, false);
        FlagBlockEncoder.writeContext(dst, 3, account, state, false, input, false);
        return dst;
    }
    function encode(bytes memory dst, bool writer, bytes32 account, uint state, bool, uint input, bool) internal pure override returns (bytes memory) {
        if (!writer) return FlagBlockEncoder.createContext(account, state, false, input, false);
        FlagBlockEncoder.writeContext(dst, 3, account, state, false, input, false);
        return dst;
    }
}
contract TestEncoderFlagsBaseline0 is FlagEncoderHarness {
    function flags(bool, bool) internal pure override returns (bool, bool) { return (false, false); }
    function encode(bytes memory dst, bool writer, bytes32 account, bytes memory state, bool, bytes memory input, bool) internal pure override returns (bytes memory value) {
        if (!writer) return E.createContext(account, state, input);
        ReservedBlockEncoder.writeContextWrap(dst, 3, account, state, input);
        return dst;
    }
    function encode(bytes memory dst, bool writer, bytes32 account, uint state, bool, uint input, bool) internal pure override returns (bytes memory value) {
        if (!writer) return E.createContext(account, state, input);
        ReservedBlockEncoder.writeContextWrap(dst, 3, account, state, input);
        return dst;
    }
}
contract TestEncoderFlagsLiteral1 is FlagEncoderHarness {
    function flags(bool, bool) internal pure override returns (bool, bool) { return (false, true); }
    function encode(bytes memory dst, bool writer, bytes32 account, bytes memory state, bool, bytes memory input, bool) internal pure override returns (bytes memory) {
        if (!writer) return FlagBlockEncoder.createContext(account, state, false, input, true);
        FlagBlockEncoder.writeContext(dst, 3, account, state, false, input, true);
        return dst;
    }
    function encode(bytes memory dst, bool writer, bytes32 account, uint state, bool, uint input, bool) internal pure override returns (bytes memory) {
        if (!writer) return FlagBlockEncoder.createContext(account, state, false, input, true);
        FlagBlockEncoder.writeContext(dst, 3, account, state, false, input, true);
        return dst;
    }
}
contract TestEncoderFlagsBaseline1 is FlagEncoderHarness {
    function flags(bool, bool) internal pure override returns (bool, bool) { return (false, true); }
    function encode(bytes memory dst, bool writer, bytes32 account, bytes memory state, bool, bytes memory input, bool) internal pure override returns (bytes memory value) {
        uint stateSize = state.length;
        uint inputSize = input.length;
        uint abs;
        if (writer) {
            value = dst;
            abs = E.pos(dst, 3);
            unchecked { abs = E.writeHeader(abs, Keys.Context, 40 + stateSize + inputSize); }
        } else {
            uint size = 48 + stateSize + inputSize;
            value = E.allocate(size);
            abs = E.pos(value, 0);
            unchecked { abs = E.writeHeader(abs, Keys.Context, size - 8); }
        }
        abs = E.write32(abs, account);
        abs = E.wrap(abs, Keys.Bytes, state, stateSize);
        E.copy(abs, input, inputSize);
    }
    function encode(bytes memory dst, bool writer, bytes32 account, uint state, bool, uint input, bool) internal pure override returns (bytes memory value) {
        uint stateSize = E.length(state);
        uint inputSize = E.length(input);
        uint abs;
        if (writer) {
            value = dst;
            abs = E.pos(dst, 3);
            unchecked { abs = E.writeHeader(abs, Keys.Context, 40 + stateSize + inputSize); }
        } else {
            uint size = 48 + stateSize + inputSize;
            value = E.allocate(size);
            abs = E.pos(value, 0);
            unchecked { abs = E.writeHeader(abs, Keys.Context, size - 8); }
        }
        abs = E.write32(abs, account);
        abs = E.wrap(abs, Keys.Bytes, uint32(state), stateSize);
        E.copy(abs, uint32(input), inputSize);
    }
}
contract TestEncoderFlagsLiteral2 is FlagEncoderHarness {
    function flags(bool, bool) internal pure override returns (bool, bool) { return (true, false); }
    function encode(bytes memory dst, bool writer, bytes32 account, bytes memory state, bool, bytes memory input, bool) internal pure override returns (bytes memory) {
        if (!writer) return FlagBlockEncoder.createContext(account, state, true, input, false);
        FlagBlockEncoder.writeContext(dst, 3, account, state, true, input, false);
        return dst;
    }
    function encode(bytes memory dst, bool writer, bytes32 account, uint state, bool, uint input, bool) internal pure override returns (bytes memory) {
        if (!writer) return FlagBlockEncoder.createContext(account, state, true, input, false);
        FlagBlockEncoder.writeContext(dst, 3, account, state, true, input, false);
        return dst;
    }
}
contract TestEncoderFlagsBaseline2 is FlagEncoderHarness {
    function flags(bool, bool) internal pure override returns (bool, bool) { return (true, false); }
    function encode(bytes memory dst, bool writer, bytes32 account, bytes memory state, bool, bytes memory input, bool) internal pure override returns (bytes memory value) {
        uint stateSize = state.length;
        uint inputSize = input.length;
        uint abs;
        if (writer) {
            value = dst;
            abs = E.pos(dst, 3);
            unchecked { abs = E.writeHeader(abs, Keys.Context, 40 + stateSize + inputSize); }
        } else {
            uint size = 48 + stateSize + inputSize;
            value = E.allocate(size);
            abs = E.pos(value, 0);
            unchecked { abs = E.writeHeader(abs, Keys.Context, size - 8); }
        }
        abs = E.write32(abs, account);
        abs = E.copy(abs, state, stateSize);
        E.wrap(abs, Keys.Bytes, input, inputSize);
    }
    function encode(bytes memory dst, bool writer, bytes32 account, uint state, bool, uint input, bool) internal pure override returns (bytes memory value) {
        uint stateSize = E.length(state);
        uint inputSize = E.length(input);
        uint abs;
        if (writer) {
            value = dst;
            abs = E.pos(dst, 3);
            unchecked { abs = E.writeHeader(abs, Keys.Context, 40 + stateSize + inputSize); }
        } else {
            uint size = 48 + stateSize + inputSize;
            value = E.allocate(size);
            abs = E.pos(value, 0);
            unchecked { abs = E.writeHeader(abs, Keys.Context, size - 8); }
        }
        abs = E.write32(abs, account);
        abs = E.copy(abs, uint32(state), stateSize);
        E.wrap(abs, Keys.Bytes, uint32(input), inputSize);
    }
}
contract TestEncoderFlagsLiteral3 is FlagEncoderHarness {
    function flags(bool, bool) internal pure override returns (bool, bool) { return (true, true); }
    function encode(bytes memory dst, bool writer, bytes32 account, bytes memory state, bool, bytes memory input, bool) internal pure override returns (bytes memory) {
        if (!writer) return FlagBlockEncoder.createContext(account, state, true, input, true);
        FlagBlockEncoder.writeContext(dst, 3, account, state, true, input, true);
        return dst;
    }
    function encode(bytes memory dst, bool writer, bytes32 account, uint state, bool, uint input, bool) internal pure override returns (bytes memory) {
        if (!writer) return FlagBlockEncoder.createContext(account, state, true, input, true);
        FlagBlockEncoder.writeContext(dst, 3, account, state, true, input, true);
        return dst;
    }
}
contract TestEncoderFlagsBaseline3 is FlagEncoderHarness {
    function flags(bool, bool) internal pure override returns (bool, bool) { return (true, true); }
    function encode(bytes memory dst, bool writer, bytes32 account, bytes memory state, bool, bytes memory input, bool) internal pure override returns (bytes memory value) {
        if (!writer) return PreviousContextCreator.createContext(account, state, input);
        ReservedBlockEncoder.writeContext(dst, 3, account, state, input);
        return dst;
    }
    function encode(bytes memory dst, bool writer, bytes32 account, uint state, bool, uint input, bool) internal pure override returns (bytes memory value) {
        if (!writer) return PreviousContextCreator.createContext(account, state, input);
        ReservedBlockEncoder.writeContext(dst, 3, account, state, input);
        return dst;
    }
}
