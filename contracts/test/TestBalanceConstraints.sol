// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;
import {LegacyBlocks} from "./LegacyBlocks.sol";
import {LegacyMemory} from "./LegacyMemory.sol";

import {Cursors} from "../utils/Cursors.sol";
import {Blocks} from "../codec/Blocks.sol";
import {BalanceConstraints, Specs, Sizes, Schemas, Execution, Executions} from "../Codec.sol";

contract TestBalanceConstraints {
    using Executions for Execution;

    function metadata() external pure returns (uint, uint, string memory) {
        return (Specs.BalanceConstraints, Sizes.BalanceConstraints, Schemas.BalanceConstraints);
    }

    function expectInput(bytes calldata input, bytes32 asset, uint amount, bool execution)
        external pure returns (BalanceConstraints memory)
    {
        if (execution) {
            Execution memory exec;
            exec.openInput(Executions.describe(Specs.Empty, Specs.BalanceConstraints, Specs.Empty, 0), 0, input);
            exec.expectBalanceConstraints(asset, amount);
            return exec.unpackBalanceConstraints();
        }
        // Establish the required bounds for the unchecked LegacyBlocks helper.
        bytes calldata first = input[:Sizes.BalanceConstraints];
        uint abs;
        assembly ("memory-safe") { abs := first.offset }
        LegacyBlocks.expectBalanceConstraints(abs, asset, amount);
        uint cur = Cursors.wrap(input[Sizes.BalanceConstraints:]);
        (BalanceConstraints memory value,) = Blocks.unpackBalanceConstraints(cur);
        return value;
    }

    function decode(bytes calldata input, uint mode)
        external pure returns (bytes32[] memory assets, uint[] memory mins, uint[] memory maxs)
    {
        uint count = input.length / Sizes.BalanceConstraints;
        assets = new bytes32[](count);
        mins = new uint[](count);
        maxs = new uint[](count);
        uint i;
        if (mode == 2) {
            Execution memory exec;
            exec.openInput(Executions.describe(Specs.Empty, Specs.BalanceConstraints, Specs.Empty, 0), 0, input);
            while (exec.more()) {
                BalanceConstraints memory value = exec.unpackBalanceConstraints();
                assets[i] = value.asset; mins[i] = value.min; maxs[i++] = value.max;
            }
        } else if (mode == 1) {
            (uint abs, uint end) = LegacyMemory.bounds(input, Sizes.BalanceConstraints);
            while (abs < end) {
                BalanceConstraints memory value = LegacyMemory.unpackBalanceConstraints(abs);
                assets[i] = value.asset; mins[i] = value.min; maxs[i] = value.max;
                ++i;
                abs += Sizes.BalanceConstraints;
            }
        } else {
            uint cur = Cursors.wrap(input);
            while (Cursors.more(cur)) {
                BalanceConstraints memory value;
                (value, cur) = Blocks.unpackBalanceConstraints(cur);
                assets[i] = value.asset; mins[i] = value.min; maxs[i++] = value.max;
            }
        }
    }
}
