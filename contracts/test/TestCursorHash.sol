// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;
import {Blocks} from "../codec/Blocks.sol";
import {Cursors} from "../utils/Cursors.sol";

abstract contract CursorHashHarness {
    function hash(uint cur) internal pure virtual returns (bytes32);

    function measure(bytes calldata source, uint start, uint end, uint metadata)
        external view returns (bytes32 digest, uint usedGas, uint allocated, bytes32 guardHash, uint zeroSlot)
    {
        uint cur = Cursors.wrap(source[start:end]) | (metadata & ~uint(type(uint64).max));
        bytes memory guard = abi.encodePacked(bytes32(uint(123)), bytes32(uint(456)));
        uint free;
        assembly ("memory-safe") {
            free := mload(0x40)
            // Hashing must tolerate dirty temporary memory, including empty ranges.
            mstore(free, not(0))
            mstore(add(free, 32), not(0))
        }
        uint beforeGas = gasleft();
        digest = hash(cur);
        usedGas = beforeGas - gasleft();
        assembly ("memory-safe") {
            allocated := sub(mload(0x40), free)
            zeroSlot := mload(0x60)
        }
        // Live allocations must survive the temporary copy.
        guardHash = keccak256(guard);
        bytes memory afterHash = abi.encode(digest);
        require(keccak256(afterHash) == keccak256(abi.encode(digest)));
    }
}

contract CursorHashCurrent is CursorHashHarness {
    function hash(uint cur) internal pure override returns (bytes32) {
        return Blocks.hash(cur);
    }
}

contract CursorHashPrimitive is CursorHashHarness {
    function hash(uint cur) internal pure override returns (bytes32) {
        return Cursors.hash(cur);
    }
}

contract CursorHashBaseline is CursorHashHarness {
    function hash(uint cur) internal pure override returns (bytes32) {
        return keccak256(Blocks.toBytes(cur));
    }
}

contract CursorLengthCurrent {
    function length(uint cur) external pure returns (uint) {
        return Blocks.length(cur);
    }
}

contract CursorLengthBaseline {
    function length(uint cur) external pure returns (uint) {
        unchecked { return uint32(cur >> 32) - uint(uint32(cur)); }
    }
}
