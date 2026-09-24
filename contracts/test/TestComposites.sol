// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;
import {Blocks} from "../codec/Blocks.sol";
import {Keys} from "../codec/Keys.sol";
import {Sizes} from "../codec/Specs.sol";
import {max32} from "../utils/Utils.sol";

/// @dev Frozen composite factories/decoders; allocator and public writers stay identical.
library PreviousComposites {
    function unpackBytes(uint abs) internal pure returns (bytes calldata value, uint end) {
        uint head;
        uint len;
        assembly ("memory-safe") {
            head := calldataload(abs)
            len := and(shr(192, head), 0xffffffff)
            value.offset := add(abs, 0x08)
            value.length := len
        }
        if (uint32(head >> 224) != uint32(Keys.Bytes)) revert InvalidBlock();
        end = abs + Sizes.Header + len;
    }
    function unpackString(uint abs) internal pure returns (bytes calldata value, uint end) {
        uint head;
        uint len;
        assembly ("memory-safe") {
            head := calldataload(abs)
            len := and(shr(192, head), 0xffffffff)
            value.offset := add(abs, 0x08)
            value.length := len
        }
        if (uint32(head >> 224) != uint32(Keys.String)) revert InvalidBlock();
        end = abs + Sizes.Header + len;
    }

    function createLabel(bytes32 namespace, string memory name) internal pure returns (bytes memory value) {
        uint len = max32(Sizes.B32 + bytes(name).length);
        value = allocate(Sizes.Header + len);
        Blocks.writeLabel(value, 0, namespace, name);
    }

    function unpackLabel(uint abs) internal pure returns (bytes32 namespace, string memory name, uint end) {
        uint limit;
        (abs, limit) = Blocks.enter(abs, Keys.Label);
        assembly ("memory-safe") {
            namespace := calldataload(abs)
        }
        bytes calldata value;
        (value, end) = unpackString(abs + 32);
        if (end != limit) revert InvalidBlock();
        name = string(value);
    }

    function createSchema(uint spec, string memory body) internal pure returns (bytes memory value) {
        uint len = max32(Sizes.B32 + bytes(body).length);
        value = allocate(Sizes.Header + len);
        Blocks.writeSchema(value, 0, spec, body);
    }

    function unpackSchema(uint abs) internal pure returns (uint spec, string memory body, uint end) {
        uint limit;
        (abs, limit) = Blocks.enter(abs, Keys.Schema);
        assembly ("memory-safe") {
            spec := calldataload(abs)
        }
        bytes calldata value;
        (value, end) = unpackString(abs + 32);
        if (end != limit) revert InvalidBlock();
        end = limit;
        body = string(value);
    }

    error InvalidBlock();
    function allocate(uint len) private pure returns (bytes memory value) {
        // Every factory overwrites the complete logical result. Only initialize
        // padding and the trailing scratch word, including when memory is dirty.
        // Factory lengths are bounded by uint32 (plus a fixed header).
        assembly ("memory-safe") {
            value := mload(0x40)
            let padded := and(add(len, 31), not(31))
            let tail := add(add(value, 0x20), padded)
            mstore(0x40, add(tail, 0x20))
            mstore(value, len)
            mstore(add(add(value, 0x20), len), 0)
        }
    }

    function createStep(uint cmd, uint value, bytes memory input) internal pure returns (bytes memory encoded) {
        uint len = max32(Sizes.Step + input.length);
        encoded = allocate(len);
        Blocks.writeStep(encoded, 0, cmd, value, input);
    }

    function createStepCopy(uint cmd, uint value, bytes calldata input) internal pure returns (bytes memory encoded) {
        uint len = max32(Sizes.Step + input.length);
        encoded = allocate(len);
        Blocks.copyStep(encoded, 0, cmd, value, input);
    }

    function createCall(uint target, uint resources, bytes memory payload) internal pure returns (bytes memory value) {
        uint len = max32(Sizes.B64 + Sizes.Header + payload.length);
        value = allocate(len);
        Blocks.writeCall(value, 0, target, resources, payload);
    }

    function createCallCopy(uint target, uint resources, bytes calldata payload) internal pure returns (bytes memory value) {
        uint len = max32(Sizes.B64 + Sizes.Header + payload.length);
        value = allocate(len);
        Blocks.copyCall(value, 0, target, resources, payload);
    }

    function createDispatch(uint portal, uint resources, bytes memory payload) internal pure returns (bytes memory value) {
        uint len = max32(Sizes.B64 + Sizes.Header + payload.length);
        value = allocate(len);
        Blocks.writeDispatch(value, 0, portal, resources, payload);
    }

    function createDispatchCopy(
        uint portal,
        uint resources,
        bytes calldata payload
    ) internal pure returns (bytes memory value) {
        uint len = max32(Sizes.B64 + Sizes.Header + payload.length);
        value = allocate(len);
        Blocks.copyDispatch(value, 0, portal, resources, payload);
    }

    function createRelay(bytes memory input, bytes memory steps) internal pure returns (bytes memory value) {
        uint len = max32(3 * Sizes.Header + input.length + steps.length);
        value = allocate(len);
        Blocks.writeRelay(value, 0, input, steps);
    }

    function createRelayCopy(bytes calldata input, bytes calldata steps) internal pure returns (bytes memory value) {
        uint len = max32(3 * Sizes.Header + input.length + steps.length);
        value = allocate(len);
        Blocks.copyRelay(value, 0, input, steps);
    }

    function createContext(
        bytes32 account,
        bytes memory state,
        bytes memory input
    ) internal pure returns (bytes memory value) {
        uint len = max32(Sizes.B32 + 2 * Sizes.Header + state.length + input.length);
        value = allocate(len);
        Blocks.writeContext(value, 0, account, state, input);
    }

    function createContextCopy(
        bytes32 account,
        bytes calldata state,
        bytes calldata input
    ) internal pure returns (bytes memory value) {
        uint len = max32(Sizes.B32 + 2 * Sizes.Header + state.length + input.length);
        value = allocate(len);
        Blocks.copyContext(value, 0, account, state, input);
    }

    function createRecover(
        uint handler,
        uint resources,
        bytes32 recoverykey,
        bytes memory witness
    ) internal pure returns (bytes memory value) {
        uint len = max32(Sizes.B96 + Sizes.Header + witness.length);
        value = allocate(len);
        Blocks.writeRecover(value, 0, handler, resources, recoverykey, witness);
    }

    function createRecoverCopy(
        uint handler,
        uint resources,
        bytes32 recoverykey,
        bytes calldata witness
    ) internal pure returns (bytes memory value) {
        uint len = max32(Sizes.B96 + Sizes.Header + witness.length);
        value = allocate(len);
        Blocks.copyRecover(value, 0, handler, resources, recoverykey, witness);
    }

    function unpackStep(
        uint abs
    ) internal pure returns (uint cmd, uint value, bytes calldata input, uint end) {
        uint limit;
        (abs, limit) = Blocks.enter(abs, Keys.Step);
        assembly ("memory-safe") {
            cmd := calldataload(abs)
            value := calldataload(add(abs, 0x20))
        }
        (input, end) = unpackBytes(abs + 64);
        if (end != limit) revert InvalidBlock();
    }

    function unpackCall(
        uint abs
    ) internal pure returns (uint target, uint resources, bytes calldata payload, uint end) {
        uint limit;
        (abs, limit) = Blocks.enter(abs, Keys.Call);
        assembly ("memory-safe") {
            target := calldataload(abs)
            resources := calldataload(add(abs, 0x20))
        }
        (payload, end) = unpackBytes(abs + 64);
        if (end != limit) revert InvalidBlock();
    }

    function unpackDispatch(
        uint abs
    ) internal pure returns (uint portal, uint resources, bytes calldata payload, uint end) {
        uint limit;
        (abs, limit) = Blocks.enter(abs, Keys.Dispatch);
        assembly ("memory-safe") {
            portal := calldataload(abs)
            resources := calldataload(add(abs, 0x20))
        }
        (payload, end) = unpackBytes(abs + 64);
        if (end != limit) revert InvalidBlock();
    }

    function unpackRelay(
        uint abs
    ) internal pure returns (bytes calldata input, bytes calldata steps, uint end) {
        uint limit;
        (abs, limit) = Blocks.enter(abs, Keys.Relay);
        (input, abs) = unpackBytes(abs);
        (steps, end) = unpackBytes(abs);
        if (end != limit) revert InvalidBlock();
    }

    function unpackContext(
        uint abs
    ) internal pure returns (bytes32 account, bytes calldata state, bytes calldata input, uint end) {
        uint limit;
        (abs, limit) = Blocks.enter(abs, Keys.Context);
        assembly ("memory-safe") {
            account := calldataload(abs)
        }
        (state, end) = unpackBytes(abs + 32);
        (input, end) = unpackBytes(end);
        if (end != limit) revert InvalidBlock();
    }

    function unpackRecover(
        uint abs
    ) internal pure returns (uint handler, uint resources, bytes32 key, bytes calldata witness, uint end) {
        uint limit;
        (abs, limit) = Blocks.enter(abs, Keys.Recover);
        assembly ("memory-safe") {
            handler := calldataload(abs)
            resources := calldataload(add(abs, 0x20))
            key := calldataload(add(abs, 0x40))
        }
        (witness, end) = unpackBytes(abs + 96);
        if (end != limit) revert InvalidBlock();
    }

    function unpackAnnotation(
        uint abs
    ) internal pure returns (uint entity, bytes calldata stream, uint end) {
        uint limit;
        (abs, limit) = Blocks.enter(abs, Keys.Annotation);
        assembly ("memory-safe") {
            entity := calldataload(abs)
        }
        (stream, end) = unpackBytes(abs + 32);
        if (end != limit) revert InvalidBlock();
    }
}

contract TestComposites {
    /// @dev Poison the future allocation and a guard word, without advancing 0x40.
    function dirty(uint len) private pure {
        assembly {
            let p := mload(0x40)
            let guard := add(add(p, 64), and(add(len, 31), not(31)))
            for { } lt(p, add(guard, 32)) { p := add(p, 32) } { mstore(p, not(0)) }
        }
    }

    /// @dev Check trailing scratch/padding, exact allocation footprint, and guard.
    function clean(bytes memory output) private pure returns (bool ok) {
        assembly {
            let len := mload(output)
            let guard := add(add(output, 64), and(add(len, 31), not(31)))
            ok := and(iszero(mload(add(add(output, 32), len))),
                and(eq(mload(0x40), guard), eq(mload(guard), not(0))))
        }
    }

    function factoryStep(bool optimized, bytes calldata a, bytes calldata /* b */, uint forgedLength)
        external view returns(uint usedGas, bytes memory output, bool cleanTail) {
        bytes memory ma = a;
        dirty(80 + a.length);
        if (forgedLength != 0) {
            assembly ("memory-safe") { a.length := forgedLength mstore(ma, forgedLength) }
        }
        uint initial = gasleft();
        output = optimized ? Blocks.createStep(11, 22, ma) : PreviousComposites.createStep(11, 22, ma);
        usedGas = initial - gasleft();
        cleanTail = clean(output);
    }
    function factoryStepCopy(bool optimized, bytes calldata a, bytes calldata /* b */, uint forgedLength)
        external view returns(uint usedGas, bytes memory output, bool cleanTail) {
        bytes memory ma = a;
        dirty(80 + a.length);
        if (forgedLength != 0) {
            assembly ("memory-safe") { a.length := forgedLength mstore(ma, forgedLength) }
        }
        uint initial = gasleft();
        output = optimized ? Blocks.createStepCopy(11, 22, a) : PreviousComposites.createStepCopy(11, 22, a);
        usedGas = initial - gasleft();
        cleanTail = clean(output);
    }
    function factoryCall(bool optimized, bytes calldata a, bytes calldata /* b */, uint forgedLength)
        external view returns(uint usedGas, bytes memory output, bool cleanTail) {
        bytes memory ma = a;
        dirty(80 + a.length);
        if (forgedLength != 0) {
            assembly ("memory-safe") { a.length := forgedLength mstore(ma, forgedLength) }
        }
        uint initial = gasleft();
        output = optimized ? Blocks.createCall(11, 22, ma) : PreviousComposites.createCall(11, 22, ma);
        usedGas = initial - gasleft();
        cleanTail = clean(output);
    }
    function factoryCallCopy(bool optimized, bytes calldata a, bytes calldata /* b */, uint forgedLength)
        external view returns(uint usedGas, bytes memory output, bool cleanTail) {
        bytes memory ma = a;
        dirty(80 + a.length);
        if (forgedLength != 0) {
            assembly ("memory-safe") { a.length := forgedLength mstore(ma, forgedLength) }
        }
        uint initial = gasleft();
        output = optimized ? Blocks.createCallCopy(11, 22, a) : PreviousComposites.createCallCopy(11, 22, a);
        usedGas = initial - gasleft();
        cleanTail = clean(output);
    }
    function factoryDispatch(bool optimized, bytes calldata a, bytes calldata /* b */, uint forgedLength)
        external view returns(uint usedGas, bytes memory output, bool cleanTail) {
        bytes memory ma = a;
        dirty(80 + a.length);
        if (forgedLength != 0) {
            assembly ("memory-safe") { a.length := forgedLength mstore(ma, forgedLength) }
        }
        uint initial = gasleft();
        output = optimized ? Blocks.createDispatch(11, 22, ma) : PreviousComposites.createDispatch(11, 22, ma);
        usedGas = initial - gasleft();
        cleanTail = clean(output);
    }
    function factoryDispatchCopy(bool optimized, bytes calldata a, bytes calldata /* b */, uint forgedLength)
        external view returns(uint usedGas, bytes memory output, bool cleanTail) {
        bytes memory ma = a;
        dirty(80 + a.length);
        if (forgedLength != 0) {
            assembly ("memory-safe") { a.length := forgedLength mstore(ma, forgedLength) }
        }
        uint initial = gasleft();
        output = optimized ? Blocks.createDispatchCopy(11, 22, a) : PreviousComposites.createDispatchCopy(11, 22, a);
        usedGas = initial - gasleft();
        cleanTail = clean(output);
    }
    function factoryRelay(bool optimized, bytes calldata a, bytes calldata b, uint forgedLength)
        external view returns(uint usedGas, bytes memory output, bool cleanTail) {
        bytes memory ma = a;
        bytes memory mb = b;
        dirty(24 + a.length + b.length);
        if (forgedLength != 0) {
            assembly ("memory-safe") { a.length := forgedLength mstore(ma, forgedLength) }
        }
        uint initial = gasleft();
        output = optimized ? Blocks.createRelay(ma, mb) : PreviousComposites.createRelay(ma, mb);
        usedGas = initial - gasleft();
        cleanTail = clean(output);
    }
    function factoryRelayCopy(bool optimized, bytes calldata a, bytes calldata b, uint forgedLength)
        external view returns(uint usedGas, bytes memory output, bool cleanTail) {
        bytes memory ma = a;
        dirty(24 + a.length + b.length);
        if (forgedLength != 0) {
            assembly ("memory-safe") { a.length := forgedLength mstore(ma, forgedLength) }
        }
        uint initial = gasleft();
        output = optimized ? Blocks.createRelayCopy(a, b) : PreviousComposites.createRelayCopy(a, b);
        usedGas = initial - gasleft();
        cleanTail = clean(output);
    }
    function factoryContext(bool optimized, bytes calldata a, bytes calldata b, uint forgedLength)
        external view returns(uint usedGas, bytes memory output, bool cleanTail) {
        bytes memory ma = a;
        bytes memory mb = b;
        dirty(56 + a.length + b.length);
        if (forgedLength != 0) {
            assembly ("memory-safe") { a.length := forgedLength mstore(ma, forgedLength) }
        }
        uint initial = gasleft();
        output = optimized ? Blocks.createContext(bytes32(uint(33)), ma, mb) : PreviousComposites.createContext(bytes32(uint(33)), ma, mb);
        usedGas = initial - gasleft();
        cleanTail = clean(output);
    }
    function factoryContextCopy(bool optimized, bytes calldata a, bytes calldata b, uint forgedLength)
        external view returns(uint usedGas, bytes memory output, bool cleanTail) {
        bytes memory ma = a;
        dirty(56 + a.length + b.length);
        if (forgedLength != 0) {
            assembly ("memory-safe") { a.length := forgedLength mstore(ma, forgedLength) }
        }
        uint initial = gasleft();
        output = optimized ? Blocks.createContextCopy(bytes32(uint(33)), a, b) : PreviousComposites.createContextCopy(bytes32(uint(33)), a, b);
        usedGas = initial - gasleft();
        cleanTail = clean(output);
    }
    function factoryRecover(bool optimized, bytes calldata a, bytes calldata /* b */, uint forgedLength)
        external view returns(uint usedGas, bytes memory output, bool cleanTail) {
        bytes memory ma = a;
        dirty(112 + a.length);
        if (forgedLength != 0) {
            assembly ("memory-safe") { a.length := forgedLength mstore(ma, forgedLength) }
        }
        uint initial = gasleft();
        output = optimized ? Blocks.createRecover(11, 22, bytes32(uint(33)), ma) : PreviousComposites.createRecover(11, 22, bytes32(uint(33)), ma);
        usedGas = initial - gasleft();
        cleanTail = clean(output);
    }
    function factoryRecoverCopy(bool optimized, bytes calldata a, bytes calldata /* b */, uint forgedLength)
        external view returns(uint usedGas, bytes memory output, bool cleanTail) {
        bytes memory ma = a;
        dirty(112 + a.length);
        if (forgedLength != 0) {
            assembly ("memory-safe") { a.length := forgedLength mstore(ma, forgedLength) }
        }
        uint initial = gasleft();
        output = optimized ? Blocks.createRecoverCopy(11, 22, bytes32(uint(33)), a) : PreviousComposites.createRecoverCopy(11, 22, bytes32(uint(33)), a);
        usedGas = initial - gasleft();
        cleanTail = clean(output);
    }
    function decodeStep(bool optimized, bytes calldata data, uint start, bool absolute)
        external view returns(uint usedGas, bytes memory output) {
        uint base; assembly ("memory-safe") { base := data.offset }
        uint abs = absolute ? start : base + start;
        uint cmd; uint value; bytes calldata input; uint end;
        uint initial = gasleft();
        if (optimized) (cmd, value, input, end) = Blocks.unpackStep(abs);
        else (cmd, value, input, end) = PreviousComposites.unpackStep(abs);
        usedGas = initial - gasleft();
        output = abi.encode(cmd, value, input, end - base);
    }
    function decodeCall(bool optimized, bytes calldata data, uint start, bool absolute)
        external view returns(uint usedGas, bytes memory output) {
        uint base; assembly ("memory-safe") { base := data.offset }
        uint abs = absolute ? start : base + start;
        uint target; uint resources; bytes calldata payload; uint end;
        uint initial = gasleft();
        if (optimized) (target, resources, payload, end) = Blocks.unpackCall(abs);
        else (target, resources, payload, end) = PreviousComposites.unpackCall(abs);
        usedGas = initial - gasleft();
        output = abi.encode(target, resources, payload, end - base);
    }
    function decodeDispatch(bool optimized, bytes calldata data, uint start, bool absolute)
        external view returns(uint usedGas, bytes memory output) {
        uint base; assembly ("memory-safe") { base := data.offset }
        uint abs = absolute ? start : base + start;
        uint portal; uint resources; bytes calldata payload; uint end;
        uint initial = gasleft();
        if (optimized) (portal, resources, payload, end) = Blocks.unpackDispatch(abs);
        else (portal, resources, payload, end) = PreviousComposites.unpackDispatch(abs);
        usedGas = initial - gasleft();
        output = abi.encode(portal, resources, payload, end - base);
    }
    function decodeRelay(bool optimized, bytes calldata data, uint start, bool absolute)
        external view returns(uint usedGas, bytes memory output) {
        uint base; assembly ("memory-safe") { base := data.offset }
        uint abs = absolute ? start : base + start;
        bytes calldata input; bytes calldata steps; uint end;
        uint initial = gasleft();
        if (optimized) (input, steps, end) = Blocks.unpackRelay(abs);
        else (input, steps, end) = PreviousComposites.unpackRelay(abs);
        usedGas = initial - gasleft();
        output = abi.encode(input, steps, end - base);
    }
    function decodeContext(bool optimized, bytes calldata data, uint start, bool absolute)
        external view returns(uint usedGas, bytes memory output) {
        uint base; assembly ("memory-safe") { base := data.offset }
        uint abs = absolute ? start : base + start;
        bytes32 account; bytes calldata state; bytes calldata input; uint end;
        uint initial = gasleft();
        if (optimized) (account, state, input, end) = Blocks.unpackContext(abs);
        else (account, state, input, end) = PreviousComposites.unpackContext(abs);
        usedGas = initial - gasleft();
        output = abi.encode(account, state, input, end - base);
    }
    function decodeRecover(bool optimized, bytes calldata data, uint start, bool absolute)
        external view returns(uint usedGas, bytes memory output) {
        uint base; assembly ("memory-safe") { base := data.offset }
        uint abs = absolute ? start : base + start;
        uint handler; uint resources; bytes32 key; bytes calldata witness; uint end;
        uint initial = gasleft();
        if (optimized) (handler, resources, key, witness, end) = Blocks.unpackRecover(abs);
        else (handler, resources, key, witness, end) = PreviousComposites.unpackRecover(abs);
        usedGas = initial - gasleft();
        output = abi.encode(handler, resources, key, witness, end - base);
    }
    function decodeAnnotation(bool optimized, bytes calldata data, uint start, bool absolute)
        external view returns(uint usedGas, bytes memory output) {
        uint base; assembly ("memory-safe") { base := data.offset }
        uint abs = absolute ? start : base + start;
        uint entity; bytes calldata stream; uint end;
        uint initial = gasleft();
        if (optimized) (entity, stream, end) = Blocks.unpackAnnotation(abs);
        else (entity, stream, end) = PreviousComposites.unpackAnnotation(abs);
        usedGas = initial - gasleft();
        output = abi.encode(entity, stream, end - base);
    }
    function factoryLabel(bool optimized, bytes calldata a, uint forgedLength)
        external view returns(uint usedGas, bytes memory output, bool cleanTail) {
        bytes memory ma = a;
        dirty(48 + a.length);
        if (forgedLength != 0) { assembly ("memory-safe") { mstore(ma, forgedLength) } }
        uint initial = gasleft();
        output = optimized ? Blocks.createLabel(bytes32(uint(33)), string(ma)) : PreviousComposites.createLabel(bytes32(uint(33)), string(ma));
        usedGas = initial - gasleft();
        cleanTail = clean(output);
    }
    function factorySchema(bool optimized, bytes calldata a, uint forgedLength)
        external view returns(uint usedGas, bytes memory output, bool cleanTail) {
        bytes memory ma = a;
        dirty(80 + a.length);
        if (forgedLength != 0) { assembly ("memory-safe") { mstore(ma, forgedLength) } }
        uint initial = gasleft();
        output = optimized ? Blocks.createSchema(11, string(ma)) : PreviousComposites.createSchema(11, string(ma));
        usedGas = initial - gasleft();
        cleanTail = clean(output);
    }
    function decodeLabel(bool optimized, bytes calldata data, uint start, bool absolute)
        external view returns(uint usedGas, bytes memory output) {
        uint base; assembly ("memory-safe") { base := data.offset }
        uint abs = absolute ? start : base + start;
        bytes32 namespace; string memory name; uint end;
        uint initial = gasleft();
        if (optimized) (namespace, name, end) = Blocks.unpackLabel(abs);
        else (namespace, name, end) = PreviousComposites.unpackLabel(abs);
        usedGas = initial - gasleft();
        output = abi.encode(namespace, name, end - base);
    }
    function decodeSchema(bool optimized, bytes calldata data, uint start, bool absolute)
        external view returns(uint usedGas, bytes memory output) {
        uint base; assembly ("memory-safe") { base := data.offset }
        uint abs = absolute ? start : base + start;
        uint spec; string memory body; uint end;
        uint initial = gasleft();
        if (optimized) (spec, body, end) = Blocks.unpackSchema(abs);
        else (spec, body, end) = PreviousComposites.unpackSchema(abs);
        usedGas = initial - gasleft();
        output = abi.encode(spec, body, end - base);
    }
}
