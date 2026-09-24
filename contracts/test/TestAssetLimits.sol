// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

import {Blocks, Memory, Cur, Decoders, Specs, Sizes, Schemas, Execution, Executions} from "../Codec.sol";

contract TestAssetLimits {
    using Decoders for Cur;

    using Executions for Execution;

    function metadata() external pure returns (uint, uint, string memory) {
        return (Specs.AssetLimits, Sizes.AssetLimits, Schemas.AssetLimits);
    }



    function expectInput(bytes calldata input, bytes32 asset, uint amount, bool execution)
        external pure returns (bytes32 nextAsset, uint nextMin, uint nextMax)
    {
        if (execution) {
            Execution memory exec;
            exec.openInput(Executions.describe(Specs.Empty, Specs.AssetLimits, Specs.Empty, 0), 0, input);
            exec.expectAssetLimits(asset, amount);
            return exec.unpackAssetLimits();
        }
        // Establish the required bounds for the unchecked Blocks helper.
        bytes calldata first = input[:Sizes.AssetLimits];
        uint abs;
        assembly ("memory-safe") { abs := first.offset }
        Blocks.expectAssetLimits(abs, asset, amount);
        Cur memory cur = Decoders.open(input[Sizes.AssetLimits:]);
        return cur.unpackAssetLimits();
    }


    function decode(bytes calldata input, uint mode)
        external pure returns (bytes32[] memory assets, uint[] memory mins, uint[] memory maxs)
    {
        uint count = input.length / Sizes.AssetLimits;
        assets = new bytes32[](count);
        mins = new uint[](count);
        maxs = new uint[](count);
        uint i;
        if (mode == 2) {
            Execution memory exec;
            exec.openInput(Executions.describe(Specs.Empty, Specs.AssetLimits, Specs.Empty, 0), 0, input);
            while (exec.more()) {
                (bytes32 asset, uint min, uint max) = exec.unpackAssetLimits();
                assets[i] = asset; mins[i] = min; maxs[i++] = max;
            }
        } else if (mode == 1) {
            (uint abs, uint end) = Memory.bounds(input, Sizes.AssetLimits);
            while (abs < end) {
                (assets[i], mins[i], maxs[i]) = Memory.unpackAssetLimits(abs);
                ++i;
                abs += Sizes.AssetLimits;
            }
        } else {
            Cur memory cur = Decoders.open(input);
            while (cur.more()) {
                (bytes32 asset, uint min, uint max) = cur.unpackAssetLimits();
                assets[i] = asset; mins[i] = min; maxs[i++] = max;
            }
        }
    }
}
