// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

import {Sizes} from "../Codec.sol";
import {Encoder} from "../codec/Encoder.sol";
import {Specs} from "../codec/Specs.sol";
import {Execution, Executions} from "../execution/Execution.sol";
import {QueryBase} from "../queries/Base.sol";
import {SchemaAnnot} from "../annotations/Schema.sol";
import {Runtime} from "../core/Runtime.sol";

using Executions for Execution;

function output32(Execution memory exec, uint spec, bytes32 value) pure {
    uint len = Specs.exact(spec, 1, 32);
    uint abs = exec.reserve(Sizes.Header + len);
    abs = Encoder.writeHeader(abs, Specs.key(spec), len);
    Encoder.write32(abs, value);
}

contract TestQuery is QueryBase {
    uint private immutable ValueSpec;
    string private constant INPUT = "uint value";

    uint private immutable descriptor;

    constructor() Runtime(0) {
        uint32 size = uint32(Sizes.B32 - Sizes.Header);
        uint valueSpec = schema(INPUT, 1, size, size, size);
        ValueSpec = valueSpec;
        (, descriptor) = query("incrementQuery", valueSpec, valueSpec);
    }

    function incrementQuery(bytes calldata input) external view returns (bytes memory) {
        return runQuery(descriptor, input, incrementOne);
    }

    function incrementOne(Execution memory exec) private view {
        uint valueSpec = ValueSpec;
        uint value = uint(exec.unpack32(valueSpec));
        output32(exec, valueSpec, bytes32(value + 1));
    }
}

contract TestKeyedLocalQuery is QueryBase {
    uint private immutable ValueSpec;
    string private constant INPUT = "{ uint value }";

    uint private immutable descriptor;

    constructor() Runtime(0) {
        uint32 size = uint32(Sizes.B32 - Sizes.Header);
        uint valueSpec = schema(INPUT, 2, size, size, size);
        ValueSpec = valueSpec;
        (, descriptor) = query("keyedLocalQuery", valueSpec, valueSpec);
    }

    function keyedLocalQuery(bytes calldata input) external view returns (bytes memory) {
        return runQuery(descriptor, input, keyedLocalOne);
    }

    function keyedLocalOne(Execution memory exec) private view {
        uint valueSpec = ValueSpec;
        uint value = uint(exec.unpack32(valueSpec));
        output32(exec, valueSpec, bytes32(value + 2));
    }
}

contract TestQualifiedSchema is SchemaAnnot {
    constructor() Runtime(0) {
        uint32 size = 64;
        schema(
            "relay.input: uint portal, uint resources",
            3,
            size,
            size,
            size
        );
    }
}
