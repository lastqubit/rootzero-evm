// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

import {rawCall, rawCallCopy, rawQuery} from "../core/Calls.sol";
import {previousRawCall, previousRawCallCopy, previousRawQuery} from "./PreviousCalls.sol";
import {Specs} from "../codec/Specs.sol";
import {PreviousSpecs} from "./PreviousSpecs.sol";

contract TestCallsSpecsOptimization {
    struct Config { uint mode; address target; bytes4 selector; bool expectEmpty; uint count; }
    struct Result { uint usedGas; uint footprint; bytes first; bytes output; }

    function probeFailure(bool optimized, Config calldata cfg, bytes calldata input)
        external returns (uint usedGas, bytes memory errorData)
    {
        uint initial = gasleft();
        try this.measure(optimized, cfg, input) returns (Result memory) {
            revert("expected failure");
        } catch (bytes memory reason) { errorData = reason; }
        usedGas = initial - gasleft();
    }

    function measure(bool optimized, Config calldata cfg, bytes calldata input)
        external payable returns (Result memory r)
    {
        bytes memory data = input;
        uint oldFree;
        assembly ("memory-safe") { oldFree := mload(0x40) }
        uint initial = gasleft();
        for (uint j; j < cfg.count; j++) {
            if (cfg.mode == 0) {
                if (optimized) r.output = rawCall(cfg.selector, cfg.target, msg.value, data, cfg.expectEmpty);
                else r.output = previousRawCall(cfg.selector, cfg.target, msg.value, data, cfg.expectEmpty);
            } else if (cfg.mode == 1) {
                if (optimized) r.output = rawCallCopy(cfg.selector, cfg.target, msg.value, input, cfg.expectEmpty);
                else r.output = previousRawCallCopy(cfg.selector, cfg.target, msg.value, input, cfg.expectEmpty);
            } else {
                if (optimized) r.output = rawQuery(cfg.selector, cfg.target, data);
                else r.output = previousRawQuery(cfg.selector, cfg.target, data);
            }
            if (j == 0) r.first = r.output;
        }
        r.usedGas = initial - gasleft();
        assembly ("memory-safe") { mstore(add(r, 32), sub(mload(0x40), oldFree)) }
        // Overwrite the next allocation to expose any under-reserved output.
        bytes memory poison = new bytes(96);
        assembly ("memory-safe") {
            mstore(add(poison, 32), not(0))
            mstore(add(poison, 64), not(0))
            mstore(add(poison, 96), not(0))
        }
    }

    function specSize(bool optimized, bool allocation, uint spec, uint count, uint repeats)
        external view returns (uint usedGas, uint result)
    {
        uint initial = gasleft();
        for (uint j; j < repeats; j++) {
            if (allocation) {
                if (optimized) result = Specs.allocation(spec, count);
                else result = PreviousSpecs.allocation(spec, count);
            } else {
                if (optimized) result = Specs.blockSize(spec);
                else result = PreviousSpecs.blockSize(spec);
            }
        }
        usedGas = initial - gasleft();
    }
}

contract TestRawReturndata {
    function returnRaw(bytes calldata input) external payable {
        assembly ("memory-safe") {
            let p := mload(0x40)
            calldatacopy(p, input.offset, input.length)
            return(p, input.length)
        }
    }

    function revertRaw(bytes calldata input) external payable {
        assembly ("memory-safe") {
            let p := mload(0x40)
            calldatacopy(p, input.offset, input.length)
            revert(p, input.length)
        }
    }

    function returnValue(bytes calldata) external payable returns (bytes memory) {
        return abi.encode(msg.value);
    }
}
