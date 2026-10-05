// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;
import {LegacyBlocks} from "./LegacyBlocks.sol";

import {Keys} from "../codec/Keys.sol";
import {Blocks} from "../codec/Blocks.sol";

import {Execution, Executions} from "../execution/Execution.sol";

import {Cursors} from "../utils/Cursors.sol";
import {BalanceConstraints, PositionConstraints} from "../core/Types.sol";

contract TestExecutionDecoders {
    using Executions for Execution;

    function inspect(uint kind, bytes calldata source, uint length, bool previous)
        external view returns (bytes memory data, uint input, uint state, uint base, uint usedGas)
    {
        require(length <= source.length);
        base = Cursors.base(source);
        uint cur = base | ((base + length) << 32) | (uint(0xa5) << 64);
        Execution memory exec;
        exec.input = cur;
        exec.state = cur;
        uint initial = gasleft();
        data = decode(exec, kind, previous);
        usedGas = initial - gasleft();
        input = exec.input;
        state = exec.state;
    }

    function decode(Execution memory exec, uint kind, bool previous) private pure returns (bytes memory data) {
        if (kind == 0) {
            bytes32 account;
            if (previous) {
                uint abs = uint32(exec.input);
                exec.input = Cursors.advance(exec.input, 40);
                account = LegacyBlocks.unpackAccount(abs);
            } else account = exec.unpackAccount();
            data = abi.encode(account);
        }
        else if (kind == 1) {
            bytes32 asset;
            if (previous) {
                uint abs = uint32(exec.input);
                exec.input = Cursors.advance(exec.input, 40);
                asset = LegacyBlocks.unpackAsset(abs);
            } else asset = exec.unpackAsset();
            data = abi.encode(asset);
        }
        else if (kind == 2) {
            uint node;
            if (previous) {
                uint abs = uint32(exec.input);
                exec.input = Cursors.advance(exec.input, 40);
                node = LegacyBlocks.unpackNode(abs);
            } else node = exec.unpackNode();
            data = abi.encode(node);
        }
        else if (kind == 3) {
            uint limits;
            if (previous) {
                uint abs = uint32(exec.input);
                exec.input = Cursors.advance(exec.input, 40);
                limits = LegacyBlocks.unpackLimits(abs);
            } else limits = exec.unpackLimits();
            data = abi.encode(limits);
        }
        else if (kind == 4) {
            bytes32 asset;
            uint amount;
            if (previous) {
                uint abs = uint32(exec.input);
                exec.input = Cursors.advance(exec.input, 72);
                (asset, amount) = LegacyBlocks.unpackAssetAmount(abs);
            } else (asset, amount) = exec.unpackAssetAmount();
            data = abi.encode(asset, amount);
        }
        else if (kind == 5) {
            bytes32 asset;
            uint amount;
            if (previous) {
                uint abs = uint32(exec.state);
                exec.state = Cursors.advance(exec.state, 72);
                (asset, amount) = LegacyBlocks.unpackBalance(abs);
            } else (asset, amount) = exec.unpackBalance();
            data = abi.encode(asset, amount);
        }
        else if (kind == 6) {
            bytes32 asset;
            bytes32 liability;
            if (previous) {
                uint abs = uint32(exec.input);
                exec.input = Cursors.advance(exec.input, 72);
                (asset, liability) = LegacyBlocks.unpackAssetLiability(abs);
            } else (asset, liability) = exec.unpackAssetLiability();
            data = abi.encode(asset, liability);
        }
        else if (kind == 7) {
            bytes32 account;
            bytes32 asset;
            if (previous) {
                uint abs = uint32(exec.input);
                exec.input = Cursors.advance(exec.input, 72);
                (account, asset) = LegacyBlocks.unpackAccountAsset(abs);
            } else (account, asset) = exec.unpackAccountAsset();
            data = abi.encode(account, asset);
        }
        else if (kind == 8) {
            uint host;
            bytes32 asset;
            if (previous) {
                uint abs = uint32(exec.input);
                exec.input = Cursors.advance(exec.input, 72);
                (host, asset) = LegacyBlocks.unpackHostAsset(abs);
            } else (host, asset) = exec.unpackHostAsset();
            data = abi.encode(host, asset);
        }
        else if (kind == 9) {
            bytes32 asset;
            uint amount;
            uint budget;
            if (previous) {
                uint abs = uint32(exec.input);
                exec.input = Cursors.advance(exec.input, 104);
                (asset, amount, budget) = LegacyBlocks.unpackBootstrap(abs);
            } else {
                // Historical fixed Bootstrap layout for this decoder comparison.
                bytes32 a; bytes32 b;
                (asset, a, b, exec.input) = Blocks.unpack96(exec.input, Keys.Bootstrap);
                amount = uint(a); budget = uint(b);
            }
            data = abi.encode(asset, amount, budget);
        }
        else if (kind == 10) {
            uint host;
            bytes32 asset;
            uint amount;
            if (previous) {
                uint abs = uint32(exec.input);
                exec.input = Cursors.advance(exec.input, 104);
                (host, asset, amount) = LegacyBlocks.unpackAllocation(abs);
            } else (host, asset, amount) = exec.unpackAllocation();
            data = abi.encode(host, asset, amount);
        }
        else if (kind == 11) {
            uint host;
            bytes32 asset;
            uint amount;
            if (previous) {
                uint abs = uint32(exec.input);
                exec.input = Cursors.advance(exec.input, 104);
                (host, asset, amount) = LegacyBlocks.unpackAllowance(abs);
            } else (host, asset, amount) = exec.unpackAllowance();
            data = abi.encode(host, asset, amount);
        }
        else if (kind == 12) {
            uint host;
            bytes32 asset;
            uint amount;
            if (previous) {
                uint abs = uint32(exec.state);
                exec.state = Cursors.advance(exec.state, 104);
                (host, asset, amount) = LegacyBlocks.unpackCustody(abs);
            } else (host, asset, amount) = exec.unpackCustody();
            data = abi.encode(host, asset, amount);
        }
        else if (kind == 13) {
            bytes32 account;
            bytes32 asset;
            uint amount;
            if (previous) {
                uint abs = uint32(exec.input);
                exec.input = Cursors.advance(exec.input, 104);
                (account, asset, amount) = LegacyBlocks.unpackAccountAmount(abs);
            } else (account, asset, amount) = exec.unpackAccountAmount();
            data = abi.encode(account, asset, amount);
        }
        else if (kind == 14) {
            uint host;
            bytes32 account;
            bytes32 asset;
            if (previous) {
                uint abs = uint32(exec.input);
                exec.input = Cursors.advance(exec.input, 104);
                (host, account, asset) = LegacyBlocks.unpackHostAccountAsset(abs);
            } else (host, account, asset) = exec.unpackHostAccountAsset();
            data = abi.encode(host, account, asset);
        }
        else if (kind == 15) {
            bytes32 asset;
            uint amount;
            bytes32 liability;
            uint debt;
            if (previous) {
                uint abs = uint32(exec.input);
                exec.input = Cursors.advance(exec.input, 136);
                (asset, amount, liability, debt) = LegacyBlocks.unpackQuote(abs);
            } else (asset, amount, liability, debt) = exec.unpackQuote();
            data = abi.encode(asset, amount, liability, debt);
        }
        else if (kind == 16) {
            bytes32 from;
            bytes32 to;
            bytes32 asset;
            uint amount;
            if (previous) {
                uint abs = uint32(exec.input);
                exec.input = Cursors.advance(exec.input, 136);
                (from, to, asset, amount) = LegacyBlocks.unpackTransaction(abs);
            } else (from, to, asset, amount) = exec.unpackTransaction();
            data = abi.encode(from, to, asset, amount);
        }
        else if (kind == 17) {
            bytes32 asset;
            uint amount;
            bytes32 liability;
            uint debt;
            bytes32 counterparty;
            if (previous) {
                uint abs = uint32(exec.state);
                exec.state = Cursors.advance(exec.state, 168);
                (asset, amount, liability, debt, counterparty) = LegacyBlocks.unpackPosition(abs);
            } else (asset, amount, liability, debt, counterparty) = exec.unpackPosition();
            data = abi.encode(asset, amount, liability, debt, counterparty);
        }
        else if (kind == 18) {
            BalanceConstraints memory value;
            if (previous) {
                uint abs = uint32(exec.input);
                exec.input = Cursors.advance(exec.input, 104);
                value = LegacyBlocks.unpackBalanceConstraints(abs);
            } else value = exec.unpackBalanceConstraints();
            data = abi.encode(value);
        }
        else if (kind == 19) {
            PositionConstraints memory value;
            if (previous) {
                uint abs = uint32(exec.input);
                exec.input = Cursors.advance(exec.input, 136);
                value = LegacyBlocks.unpackPositionConstraints(abs);
            } else value = exec.unpackPositionConstraints();
            data = abi.encode(value);
        }
    }
}

contract TestExecutionCompositeDecoders {
    using Executions for Execution;

    function inspect(uint kind, bytes calldata source, uint length)
        external pure returns (uint[3] memory values, uint firstCur, uint secondCur, uint input, uint state, uint base)
    {
        require(length <= source.length);
        base = Cursors.base(source);
        Execution memory exec;
        exec.input = base | ((base + length) << 32) | (uint(0xa5) << 64);
        exec.state = 0x12345678;
        if (kind == 0) firstCur = exec.unpackBytes();
        else if (kind == 1) firstCur = exec.unpackString();
        else if (kind == 2) (firstCur, secondCur) = exec.unpackRelay();
        else if (kind == 3) (values[0], firstCur) = exec.unpackAnnotation();
        else if (kind == 4) {
            bytes32 namespace;
            (namespace, firstCur) = exec.unpackLabel();
            values[0] = uint(namespace);
        } else if (kind == 5) (values[0], firstCur) = exec.unpackSchema();
        else if (kind == 6) {
            bytes32 account;
            (account, firstCur, secondCur) = exec.unpackContext();
            values[0] = uint(account);
        } else if (kind == 7) (values[0], values[1], firstCur) = exec.unpackStep();
        else if (kind == 8) (values[0], values[1], firstCur) = exec.unpackCall();
        else if (kind == 9) (values[0], values[1], firstCur) = exec.unpackDispatch();
        else if (kind == 10) {
            bytes32 key;
            (values[0], values[1], key, firstCur) = exec.unpackRecover();
            values[2] = uint(key);
        }
        input = exec.input;
        state = exec.state;
    }
}
