// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

import {Execution, Executions, Encoder, Position, POSITION_HEADER} from "../Codec.sol";

/// @dev Experiments only. Timed region assumes an opened execution and memory Position.
abstract contract PositionLogHarness {
    using Executions for Execution;
    bytes32 internal constant TOPIC = keccak256("Positioned(bytes32,bytes32,uint256,bytes32,uint256,bytes32,uint256)");
    bytes32 internal constant BYTES_TOPIC = keccak256("PositionBytes(bytes32,uint256,bytes)");
    bytes32 internal constant RAW_TOPIC = keccak256("rootzero.position.block.v1");
    // Historical ABI baseline only; production position logs use Logs.
    event Positioned(bytes32 indexed account, bytes32 asset, uint amount, bytes32 liability, uint debt, bytes32 counterparty, uint codes);
    event PositionBytes(bytes32 indexed account, uint codes, bytes position);

    function one(Execution memory exec, Position memory p, uint codes) internal virtual;
    function afterBatch(Execution memory, uint, uint, uint) internal virtual {}

    function measure(Position memory p, bytes32 account, uint codes, uint capacity, uint count, bool sentinels)
        external returns (uint used, bytes memory output)
    {
        Execution memory exec;
        exec.account = account;
        (exec.buffer, exec.output) = Encoder.init(capacity);
        if (sentinels) exec.outputCodes(0x1234);
        uint start = uint32(exec.output);
        uint initial = gasleft();
        for (uint i; i < count; ++i) one(exec, p, codes);
        afterBatch(exec, codes, start, count);
        used = initial - gasleft();
        if (sentinels) exec.outputCodes(0x5678);
        output = exec.finish();
    }

    function copyPosition(Execution memory exec, Position memory p) internal pure returns (uint blockAbs) {
        blockAbs = exec.reserve(168);
        assembly ("memory-safe") {
            mstore(blockAbs, shl(192, POSITION_HEADER))
            mcopy(add(blockAbs, 8), p, 160)
        }
    }
    function fastCopyPosition(Execution memory exec, Position memory p) internal pure returns (uint blockAbs) {
        assembly ("memory-safe") {
            let cur := mload(add(exec, 128))
            let written := and(cur, 0xffffffff)
            let capacity := and(shr(32, cur), 0xffffffff)
            if iszero(lt(sub(capacity, written), 168)) {
                blockAbs := add(add(mload(add(exec, 160)), 32), written)
                mstore(add(exec, 128), add(cur, 168))
            }
        }
        if (blockAbs == 0) blockAbs = exec.reserve(168);
        assembly ("memory-safe") {
            mstore(blockAbs, shl(192, POSITION_HEADER))
            mcopy(add(blockAbs, 8), p, 160)
        }
    }

    function inlineCopyPosition(Execution memory exec, Position memory p) internal pure returns (uint blockAbs) {
        assembly ("memory-safe") {
            let cur := mload(add(exec, 128))
            let written := and(cur, 0xffffffff)
            let capacity := and(shr(32, cur), 0xffffffff)
            let buffer := mload(add(exec, 160))
            if lt(sub(capacity, written), 168) {
                let required := add(written, 168)
                switch capacity
                case 0 { capacity := 64 }
                default { capacity := mul(capacity, 2) }
                for {} lt(capacity, required) {} { capacity := mul(capacity, 2) }
                if gt(capacity, 0xffffffff) {
                    mstore(0, shl(224, 0xf20577e5)) // ValueOverflow()
                    revert(0, 4)
                }
                let grown := mload(0x40)
                let padded := add(and(add(capacity, 31), not(31)), 32)
                mstore(grown, padded)
                mstore(0x40, add(add(grown, 32), padded))
                mcopy(add(grown, 32), add(buffer, 32), written)
                buffer := grown
                mstore(add(exec, 160), buffer)
                cur := or(and(cur, not(0xffffffffffffffff)), or(shl(32, capacity), written))
            }
            blockAbs := add(add(buffer, 32), written)
            mstore(add(exec, 128), add(cur, 168))
            mstore(blockAbs, shl(192, POSITION_HEADER))
            mcopy(add(blockAbs, 8), p, 160)
        }
    }

    function verifyMany(Position[] memory positions, bytes32 account, uint codes, uint capacity)
        external returns (bytes memory)
    {
        Execution memory exec;
        exec.account = account;
        (exec.buffer, exec.output) = Encoder.init(capacity);
        exec.outputCodes(0x1234);
        uint start = uint32(exec.output);
        for (uint i; i < positions.length; ++i) one(exec, positions[i], codes);
        afterBatch(exec, codes, start, positions.length);
        exec.outputCodes(0x5678);
        return exec.finish();
    }

}

contract PositionLogSeparate is PositionLogHarness {
    using Executions for Execution;
    function one(Execution memory exec, Position memory p, uint codes) internal override {
        emit Positioned(exec.account, p.asset, p.amount, p.liability, p.debt, p.counterparty, codes);
        exec.outputPosition(p);
    }
}

contract PositionLogReuse is PositionLogHarness {
    using Executions for Execution;
    function one(Execution memory exec, Position memory p, uint codes) internal override {
        exec.outputPosition(p);
        uint payload = Encoder.pos(exec.buffer, uint32(exec.output) - 160);
        bytes32 account = exec.account;
        bytes32 topic = TOPIC;
        assembly ("memory-safe") {
            // The writer owns a retained scratch word after capacity.
            mstore(add(payload, 160), codes)
            log2(payload, 192, topic, account)
        }
    }
}

contract PositionLogFused is PositionLogHarness {
    using Executions for Execution;
    function one(Execution memory exec, Position memory p, uint codes) internal override {
        uint blockAbs = copyPosition(exec, p);
        bytes32 account = exec.account;
        bytes32 topic = TOPIC;
        assembly ("memory-safe") {
            mstore(add(blockAbs, 168), codes)
            log2(add(blockAbs, 8), 192, topic, account)
        }
    }
}

contract PositionLogFusedStores is PositionLogHarness {
    using Executions for Execution;
    function one(Execution memory exec, Position memory p, uint codes) internal override {
        uint blockAbs = exec.reserve(168);
        bytes32 account = exec.account;
        bytes32 topic = TOPIC;
        assembly ("memory-safe") {
            mstore(blockAbs, shl(192, POSITION_HEADER))
            mstore(add(blockAbs, 8), mload(p))
            mstore(add(blockAbs, 40), mload(add(p, 32)))
            mstore(add(blockAbs, 72), mload(add(p, 64)))
            mstore(add(blockAbs, 104), mload(add(p, 96)))
            mstore(add(blockAbs, 136), mload(add(p, 128)))
            mstore(add(blockAbs, 168), codes)
            log2(add(blockAbs, 8), 192, topic, account)
        }
    }
}

contract PositionLogRawBlock is PositionLogHarness {
    using Executions for Execution;
    function one(Execution memory exec, Position memory p, uint codes) internal override {
        uint blockAbs = copyPosition(exec, p);
        bytes32 account = exec.account;
        bytes32 topic = RAW_TOPIC;
        assembly ("memory-safe") {
            // Temporarily borrow the buffer length/previous output, then restore it.
            let start := sub(blockAbs, 32)
            let saved := mload(start)
            mstore(start, codes)
            log2(start, 200, topic, account)
            mstore(start, saved)
        }
    }
}

contract PositionLogBytes is PositionLogHarness {
    using Executions for Execution;
    function one(Execution memory exec, Position memory p, uint codes) internal override {
        uint blockAbs = copyPosition(exec, p);
        bytes32 account = exec.account;
        bytes32 topic = BYTES_TOPIC;
        assembly ("memory-safe") {
            // ABI-compatible bytes event. Scratch is ephemeral and owns no output.
            let start := mload(0x40)
            mstore(start, codes)
            mstore(add(start, 32), 64)
            mstore(add(start, 64), 168)
            mstore(add(start, 256), 0)
            mcopy(add(start, 96), blockAbs, 168)
            log2(start, 288, topic, account)
        }
    }
}

contract PositionLogAnonymousIndexed is PositionLogHarness {
    using Executions for Execution;
    function one(Execution memory exec, Position memory p, uint codes) internal override {
        uint blockAbs = copyPosition(exec, p);
        bytes32 account = exec.account;
        assembly ("memory-safe") {
            mstore(add(blockAbs, 168), codes)
            log1(add(blockAbs, 8), 192, account)
        }
    }
}

contract PositionLogAnonymous is PositionLogHarness {
    using Executions for Execution;
    function one(Execution memory exec, Position memory p, uint codes) internal override {
        uint blockAbs = copyPosition(exec, p);
        bytes32 account = exec.account;
        assembly ("memory-safe") {
            // Last 24 bytes of prior output/length + 8-byte POSITION header.
            let start := sub(blockAbs, 24)
            let saved := mload(start)
            mstore(start, account)
            mstore(add(blockAbs, 168), codes)
            log0(start, 224)
            mstore(start, saved)
        }
    }
}

contract PositionLogCompact is PositionLogHarness {
    using Executions for Execution;
    function one(Execution memory exec, Position memory p, uint codes) internal override {
        copyPosition(exec, p);
        bytes32 account = exec.account;
        assembly ("memory-safe") {
            function width(x) -> n {
                if x {
                    n := 1
                    if shr(128, x) { n := add(n, 16) x := shr(128, x) }
                    if shr(64, x) { n := add(n, 8) x := shr(64, x) }
                    if shr(32, x) { n := add(n, 4) x := shr(32, x) }
                    if shr(16, x) { n := add(n, 2) x := shr(16, x) }
                    if shr(8, x) { n := add(n, 1) }
                }
            }
            let amount := mload(add(p, 32))
            let debt := mload(add(p, 96))
            let a := width(amount)
            let d := width(debt)
            let c := width(codes)
            let start := mload(0x40)
            // Three one-byte widths, four full-width identifiers, then minimal integers.
            mstore(start, shl(232, or(or(shl(16, a), shl(8, d)), c)))
            mstore(add(start, 3), account)
            mstore(add(start, 35), mload(p))
            mstore(add(start, 67), mload(add(p, 64)))
            mstore(add(start, 99), mload(add(p, 128)))
            let cur := add(start, 131)
            mstore(cur, shl(mul(sub(32, a), 8), amount))
            cur := add(cur, a)
            mstore(cur, shl(mul(sub(32, d), 8), debt))
            cur := add(cur, d)
            mstore(cur, shl(mul(sub(32, c), 8), codes))
            log0(start, add(sub(cur, start), c))
        }
    }
}

contract PositionLogFusedFast is PositionLogHarness {
    using Executions for Execution;
    function one(Execution memory exec, Position memory p, uint codes) internal override {
        uint blockAbs = fastCopyPosition(exec, p);
        bytes32 account = exec.account;
        bytes32 topic = TOPIC;
        assembly ("memory-safe") {
            mstore(add(blockAbs, 168), codes)
            log2(add(blockAbs, 8), 192, topic, account)
        }
    }
}

contract PositionLogAnonymousFast is PositionLogHarness {
    using Executions for Execution;
    function one(Execution memory exec, Position memory p, uint codes) internal override {
        uint blockAbs = fastCopyPosition(exec, p);
        bytes32 account = exec.account;
        assembly ("memory-safe") {
            // Last 24 bytes of prior output/length + 8-byte POSITION header.
            let start := sub(blockAbs, 24)
            let saved := mload(start)
            mstore(start, account)
            mstore(add(blockAbs, 168), codes)
            log0(start, 224)
            mstore(start, saved)
        }
    }
}

contract PositionLogAdaptive is PositionLogHarness {
    using Executions for Execution;
    function one(Execution memory exec, Position memory p, uint codes) internal override {
        uint blockAbs = copyPosition(exec, p);
        bytes32 account = exec.account;
        assembly ("memory-safe") {
            let amount := mload(add(p, 32))
            let debt := mload(add(p, 96))
            let size := 224
            // Packet length selects the layout: 128, 156, 176, or 224 bytes.
            switch or(or(amount, debt), codes)
            case 0 { size := 128 }
            default {
                switch iszero(shr(128, or(or(amount, debt), codes)))
                case 1 {
                    size := 176
                    if and(iszero(shr(64, or(amount, debt))), iszero(shr(96, codes))) { size := 156 }
                }
            }
            switch size
            case 224 {
                let start := sub(blockAbs, 24)
                let saved := mload(start)
                mstore(start, account)
                mstore(add(blockAbs, 168), codes)
                log0(start, 224)
                mstore(start, saved)
            }
            default {
                let start := mload(0x40)
                mstore(start, account)
                mstore(add(start, 32), mload(p))
                mstore(add(start, 64), mload(add(p, 64)))
                mstore(add(start, 96), mload(add(p, 128)))
                switch size
                case 156 {
                    mstore(add(start, 128), or(or(shl(192, amount), shl(128, debt)), shl(32, codes)))
                }
                case 176 {
                    mstore(add(start, 128), or(shl(128, amount), debt))
                    mstore(add(start, 160), shl(128, codes))
                }
                log0(start, size)
            }
        }
    }
}

contract PositionLogCompact64 is PositionLogHarness {
    function one(Execution memory exec, Position memory p, uint codes) internal override {
        uint blockAbs = copyPosition(exec, p);
        bytes32 account = exec.account;
        assembly ("memory-safe") {
            let amount := mload(add(p, 32))
            let debt := mload(add(p, 96))
            switch or(shr(64, or(amount, debt)), shr(96, codes))
            case 0 {
                let start := mload(0x40)
                mstore(start, account)
                mstore(add(start, 32), mload(p))
                mstore(add(start, 64), mload(add(p, 64)))
                mstore(add(start, 96), mload(add(p, 128)))
                mstore(add(start, 128), or(or(shl(192, amount), shl(128, debt)), shl(32, codes)))
                log0(start, 156)
            }
            default {
                let start := sub(blockAbs, 24)
                let saved := mload(start)
                mstore(start, account)
                mstore(add(blockAbs, 168), codes)
                log0(start, 224)
                mstore(start, saved)
            }
        }
    }
}

contract PositionLogBatch is PositionLogHarness {
    function one(Execution memory exec, Position memory p, uint) internal pure override {
        copyPosition(exec, p);
    }
    function afterBatch(Execution memory exec, uint codes, uint offset, uint count) internal override {
        bytes32 account = exec.account;
        uint source = Encoder.pos(exec.buffer, offset);
        assembly ("memory-safe") {
            if count {
                let start := mload(0x40)
                mstore(start, account)
                mstore(add(start, 32), codes)
                let cur := add(start, 64)
                let end := add(cur, mul(count, 160))
                for {} lt(cur, end) { cur := add(cur, 160) source := add(source, 168) } {
                    mcopy(cur, add(source, 8), 160)
                }
                log0(start, sub(end, start))
            }
        }
    }
}

contract PositionLogFusedInline is PositionLogHarness {
    using Executions for Execution;
    function one(Execution memory exec, Position memory p, uint codes) internal override {
        uint blockAbs = inlineCopyPosition(exec, p);
        bytes32 account = exec.account;
        bytes32 topic = TOPIC;
        assembly ("memory-safe") {
            mstore(add(blockAbs, 168), codes)
            log2(add(blockAbs, 8), 192, topic, account)
        }
    }
}

contract PositionLogAnonymousInline is PositionLogHarness {
    using Executions for Execution;
    function one(Execution memory exec, Position memory p, uint codes) internal override {
        uint blockAbs = inlineCopyPosition(exec, p);
        bytes32 account = exec.account;
        assembly ("memory-safe") {
            // Last 24 bytes of prior output/length + 8-byte POSITION header.
            let start := sub(blockAbs, 24)
            let saved := mload(start)
            mstore(start, account)
            mstore(add(blockAbs, 168), codes)
            log0(start, 224)
            mstore(start, saved)
        }
    }
}

contract PositionLogCompact64Inline is PositionLogHarness {
    function one(Execution memory exec, Position memory p, uint codes) internal override {
        uint blockAbs = inlineCopyPosition(exec, p);
        bytes32 account = exec.account;
        assembly ("memory-safe") {
            let amount := mload(add(p, 32))
            let debt := mload(add(p, 96))
            switch or(shr(64, or(amount, debt)), shr(96, codes))
            case 0 {
                let start := mload(0x40)
                mstore(start, account)
                mstore(add(start, 32), mload(p))
                mstore(add(start, 64), mload(add(p, 64)))
                mstore(add(start, 96), mload(add(p, 128)))
                mstore(add(start, 128), or(or(shl(192, amount), shl(128, debt)), shl(32, codes)))
                log0(start, 156)
            }
            default {
                let start := sub(blockAbs, 24)
                let saved := mload(start)
                mstore(start, account)
                mstore(add(blockAbs, 168), codes)
                log0(start, 224)
                mstore(start, saved)
            }
        }
    }
}

contract PositionLogAdaptiveInline is PositionLogHarness {
    using Executions for Execution;
    function one(Execution memory exec, Position memory p, uint codes) internal override {
        uint blockAbs = inlineCopyPosition(exec, p);
        bytes32 account = exec.account;
        assembly ("memory-safe") {
            let amount := mload(add(p, 32))
            let debt := mload(add(p, 96))
            let size := 224
            // Packet length selects the layout: 128, 156, 176, or 224 bytes.
            switch or(or(amount, debt), codes)
            case 0 { size := 128 }
            default {
                switch iszero(shr(128, or(or(amount, debt), codes)))
                case 1 {
                    size := 176
                    if and(iszero(shr(64, or(amount, debt))), iszero(shr(96, codes))) { size := 156 }
                }
            }
            switch size
            case 224 {
                let start := sub(blockAbs, 24)
                let saved := mload(start)
                mstore(start, account)
                mstore(add(blockAbs, 168), codes)
                log0(start, 224)
                mstore(start, saved)
            }
            default {
                let start := mload(0x40)
                mstore(start, account)
                mstore(add(start, 32), mload(p))
                mstore(add(start, 64), mload(add(p, 64)))
                mstore(add(start, 96), mload(add(p, 128)))
                switch size
                case 156 {
                    mstore(add(start, 128), or(or(shl(192, amount), shl(128, debt)), shl(32, codes)))
                }
                case 176 {
                    mstore(add(start, 128), or(shl(128, amount), debt))
                    mstore(add(start, 160), shl(128, codes))
                }
                log0(start, size)
            }
        }
    }
}

contract PositionLogBatchCompact is PositionLogHarness {
    function one(Execution memory exec, Position memory p, uint) internal pure override {
        inlineCopyPosition(exec, p);
    }
    function afterBatch(Execution memory exec, uint codes, uint offset, uint count) internal override {
        bytes32 account = exec.account;
        uint source = Encoder.pos(exec.buffer, offset);
        assembly ("memory-safe") {
            if count {
                let combined := 0
                let sourceEnd := add(source, mul(count, 168))
                for { let cur := source } lt(cur, sourceEnd) { cur := add(cur, 168) } {
                    combined := or(combined, or(mload(add(cur, 40)), mload(add(cur, 104))))
                }
                let kind := 0
                if iszero(or(shr(64, combined), shr(96, codes))) { kind := 1 }
                if iszero(or(combined, codes)) { kind := 2 }
                let start := mload(0x40)
                mstore(start, shl(248, kind))
                mstore(add(start, 1), account)
                let target := add(start, 33)
                switch kind
                case 0 {
                    mstore(target, codes)
                    target := add(target, 32)
                }
                case 1 {
                    mstore(target, shl(160, codes))
                    target := add(target, 12)
                }
                for {} lt(source, sourceEnd) { source := add(source, 168) } {
                    switch kind
                    case 0 {
                        mcopy(target, add(source, 8), 160)
                        target := add(target, 160)
                    }
                    default {
                        mstore(target, mload(add(source, 8)))
                        mstore(add(target, 32), mload(add(source, 72)))
                        mstore(add(target, 64), mload(add(source, 136)))
                        target := add(target, 96)
                        if eq(kind, 1) {
                            mstore(target, or(shl(192, mload(add(source, 40))), shl(128, mload(add(source, 104)))))
                            target := add(target, 16)
                        }
                    }
                }
                log0(start, sub(target, start))
            }
        }
    }
}
