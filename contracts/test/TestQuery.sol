// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

import {Sizes} from "../Codec.sol";
import {Blocks} from "../codec/Blocks.sol";
import {Specs} from "../codec/Specs.sol";
import {Execution, Executions} from "../execution/Execution.sol";
import {QueryBase} from "../queries/Base.sol";
import {SchemaAnnot} from "../annotations/Schema.sol";
import {Runtime} from "../core/Runtime.sol";

using Executions for Execution;

function output32(Execution memory exec, uint spec, bytes32 value) pure {
    uint len = Specs.exact(spec, 1, 32);
    uint i = exec.reserve(Sizes.Header + len, Sizes.B32);
    Blocks.write32(exec.output, i, Specs.key(spec), value);
}

contract TestQuery is QueryBase {
    uint private immutable ValueSpec;
    string private constant INPUT = "uint value";

    uint private immutable descriptor;

    constructor() Runtime(0) {
        uint32 size = uint32(Sizes.B32 - Sizes.Header);
        uint valueSpec = schema(1, size, size, size, INPUT);
        ValueSpec = valueSpec;
        (, descriptor) = query("incrementQuery", valueSpec, valueSpec);
    }

    function incrementQuery(bytes calldata input) external view returns (bytes memory out) {
        Execution memory exec = openInput(input, descriptor);
        uint valueSpec = ValueSpec;

        while (exec.more()) {
            uint foo = uint(exec.unpack32(valueSpec));
            output32(exec, valueSpec, bytes32(foo + 1));
        }

        out = close(exec);
    }
}

contract TestKeyedLocalQuery is QueryBase {
    uint private immutable ValueSpec;
    string private constant INPUT = "{ uint value }";

    uint private immutable descriptor;

    constructor() Runtime(0) {
        uint32 size = uint32(Sizes.B32 - Sizes.Header);
        uint valueSpec = schema(2, size, size, size, INPUT);
        ValueSpec = valueSpec;
        (, descriptor) = query("keyedLocalQuery", valueSpec, valueSpec);
    }

    function keyedLocalQuery(bytes calldata input) external view returns (bytes memory out) {
        Execution memory exec = openInput(input, descriptor);
        uint valueSpec = ValueSpec;

        while (exec.more()) {
            uint foo = uint(exec.unpack32(valueSpec));
            output32(exec, valueSpec, bytes32(foo + 2));
        }

        out = close(exec);
    }
}

contract TestQualifiedSchema is SchemaAnnot {
    constructor() Runtime(0) {
        uint32 size = 64;
        schema(
            3,
            size,
            size,
            size,
            "uint portal, uint resources",
            bytes32("relay.input")
        );
    }
}
