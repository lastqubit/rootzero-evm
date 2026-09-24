// SPDX-License-Identifier: MIT
pragma solidity ^0.8.33;

// Example 9: Nested Swap Input
//
// A SWAP block contains position-shaped inline input, compact configuration, hook data,
// and an always-present list of context-local SWAP_HOP blocks:
//
//   #swap {
//       uint32 fee,
//       int32 tickSpacing,
//       uint hook,
//       #bytes as hookData,
//       bytes32 asset,
//       uint amount,
//       bytes32 liability,
//       uint debt,
//       many #swapHop
//   }
//
//   #swapHop {
//       bytes32 asset,
//       uint32 fee,
//       int32 tickSpacing,
//       uint hook,
//       #bytes as hookData
//   }

import {Host, SchemaAnnot} from "../contracts/Core.sol";
import {Blocks, CommandBase, Cur, Decoders, Execution, Executions, Position, Specs} from "../contracts/Commands.sol";

using Decoders for Cur;
using Executions for Execution;

abstract contract SwapHopInput is SchemaAnnot {
    string private constant INPUT = "swapHop: { bytes32 asset, uint32 fee, int32 tickSpacing, uint hook, #bytes as hookData }";

    uint private immutable inputSpec;

    struct SwapHop {
        bytes32 asset;
        uint32 fee;
        int32 tickSpacing;
        uint hook;
        bytes hookData;
    }

    constructor(uint32 key) {
        inputSpec = schema(INPUT, key, 80, 0, 128);
    }

    function unpackSwapHop(Cur memory hops) internal view returns (SwapHop memory value) {
        (uint abs, uint end) = hops.enter(inputSpec, 72);

        value.asset = Blocks.read32(abs);
        value.fee = uint32(Blocks.read4(abs + 32));
        value.tickSpacing = int32(uint32(Blocks.read4(abs + 36)));
        value.hook = uint(Blocks.read32(abs + 40));
        value.hookData = hops.unpackBytes();

        hops.expect(end);
    }
}

abstract contract SwapInput is SchemaAnnot {
    string private constant INPUT =
        "{ uint32 fee, int32 tickSpacing, uint hook, #bytes as hookData, bytes32 asset, uint amount, bytes32 liability, uint debt, many #swapHop }";

    uint internal immutable swapSpec;

    struct SwapContext {
        uint32 fee;
        int32 tickSpacing;
        uint hook;
        bytes hookData;
    }

    constructor(uint32 key) {
        swapSpec = schema(INPUT, key, 184, 0, 512);
    }

    function unpackSwap(
        Execution memory exec
    ) internal view returns (Position memory position, SwapContext memory context, Cur memory hops) {
        (uint abs, uint end) = exec.enter(swapSpec, 40);

        context.fee = uint32(Blocks.read4(abs));
        context.tickSpacing = int32(uint32(Blocks.read4(abs + 4)));
        context.hook = uint(Blocks.read32(abs + 8));
        context.hookData = exec.unpackBytes();
        uint positionAbs = exec.take(128);
        position.asset = Blocks.read32(positionAbs);
        position.amount = uint(Blocks.read32(positionAbs + 32));
        position.liability = Blocks.read32(positionAbs + 64);
        position.debt = uint(Blocks.read32(positionAbs + 96));
        hops = exec.list();

        exec.expect(end);
    }
}

abstract contract SwapCommand is CommandBase, SwapHopInput, SwapInput {
    uint private immutable descriptor;

    constructor() SwapHopInput(2) SwapInput(1) {
        (, descriptor) = command("swap", Specs.Empty, swapSpec, Specs.Empty, 0);
    }

    function swap(Position memory, SwapContext memory, Cur memory hops) internal virtual {
        while (hops.more()) unpackSwapHop(hops);
    }

    function swap(
        bytes calldata commandContext
    ) external onlyCommand returns (bytes memory, uint) {
        return runCommand(commandContext, descriptor, swapOne);
    }

    function swapOne(Execution memory exec) private {
        (Position memory position, SwapContext memory context, Cur memory hops) = unpackSwap(exec);
        swap(position, context, hops);
    }
}

contract ExampleHost is Host, SwapCommand {
    constructor(uint rootzero) Host(rootzero) {}
}
