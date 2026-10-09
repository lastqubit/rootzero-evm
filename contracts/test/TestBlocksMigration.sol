// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;
import {PreviousNamingEncoder} from "./PreviousNaming.sol";
import {PreviousExecutionCost} from "./PreviousExecutionCost.sol";
import {MalformedBlocks} from "./LegacyErrors.sol";
import {LegacyBlocks} from "./LegacyBlocks.sol";
import {LegacyMemory} from "./LegacyMemory.sol";

import {Blocks} from "../codec/Blocks.sol";
import {PreviousMemoryBlocks as MemoryBlocks} from "./PreviousMemoryBlocks.sol";
import {Encoder} from "../codec/Encoder.sol";
import {Execution, Executions} from "../execution/Execution.sol";
import {Headers} from "../codec/Headers.sol";
import {Cursors} from "../utils/Cursors.sol";
import {Sizes} from "../codec/Specs.sol";
import {LegacyHeaders} from "./LegacyHeaders.sol";
import {Keys} from "../codec/Keys.sol";
import {Position} from "../core/Types.sol";
import {UnexpectedState, UnexpectedInput, InvalidAsset, OutOfBounds, InvalidBlock} from "../utils/Errors.sol";

// Benchmark-only copies of production execute bodies, with identical observable
// hooks. Candidate changes only cursor construction, decoding, and advancement.
// No production callers or codec APIs are changed by this experiment.
abstract contract MigrationHooks {
    bytes32 constant chainAsset = bytes32(uint(1));
    uint public checksum;
    function debitAccount(bytes32 account, bytes32 asset, uint amount) internal {
        unchecked { checksum += uint(account) ^ uint(asset) ^ amount; }
    }
    function creditAccount(bytes32 account, bytes32 asset, uint amount) internal { debitAccount(account, asset, amount); }
    function cashout(bytes32 account, uint amount) internal { debitAccount(account, chainAsset, amount); }
    function settle(bytes32 account, Position memory position) internal {
        unchecked { checksum += uint(account) ^ uint(position.asset) ^ position.amount ^ uint(position.liability) ^ position.debt ^ uint(position.counterparty); }
        position.amount = 0;
    }
    function enforceAdmin(bytes32 account, address) internal pure { require(account == bytes32(uint(9))); }
    function authorizeNode(uint node) internal { unchecked { checksum += node; } }
}

contract BlocksMigrationBaseline is MigrationHooks {
    function executeBootstrap(
        bytes32 account,
        bytes memory state,
        bytes calldata input,
        uint value
    ) internal returns (bool handled, bytes memory output, uint credit) {
        if (state.length != 0) revert UnexpectedState();
        (uint abs, uint end) = Cursors.bounds(input, 104);
        // floor(input.length / 104) * 72 <= input.length, so multiplication cannot overflow.
        uint cur;
        unchecked {
            (output, cur) = Encoder.init(input.length / 104 * Sizes.Balance);
        }
        credit = value;

        while (abs < end) {
            (bytes32 asset, uint amount, uint budget) = LegacyBlocks.unpackBootstrap(abs);
            credit = bootstrap(account, asset, amount, budget, credit);
            (output, cur) = Encoder.writeBalance(cur, output, asset, amount);
            unchecked {
                abs += 104;
            }
        }

        output = Encoder.finish(cur, output);
        return (true, output, credit);
    }
    function bootstrap(
        bytes32 account,
        bytes32 asset,
        uint amount,
        uint budget,
        uint value
    ) private returns (uint) {
        if (asset == chainAsset) {
            uint funded = amount < value ? amount : value;
            unchecked {
                amount -= funded;
                value -= funded;
            }
            amount += budget;
        } else {
            if (amount != 0) debitAccount(account, asset, amount);
            amount = budget;
        }

        if (amount != 0) debitAccount(account, chainAsset, amount);
        return value + budget;
    }
    function measureBootstrap(bytes memory state, bytes calldata input, uint value) external returns (
        uint usedGas, bool handled, bytes memory output, uint credit, uint result
    ) {
        uint beforeGas = gasleft();
        (handled, output, credit) = executeBootstrap(bytes32(uint(9)), state, input, value);
        usedGas = beforeGas - gasleft();
        result = checksum;
    }
    function executeDebitAccount(
        bytes32 account,
        bytes memory state,
        bytes calldata input,
        uint value
    ) internal returns (bool handled, bytes memory output, uint credit) {
        if (state.length != 0) revert UnexpectedState();
        (uint abs, uint end) = Cursors.bounds(input, Sizes.AssetAmount);
        uint cur;
        (output, cur) = Encoder.init(input.length);

        while (abs < end) {
            (bytes32 asset, uint amount) = LegacyBlocks.unpackAssetAmount(abs);
            debitAccount(account, asset, amount);
            (output, cur) = Encoder.writeBalance(cur, output, asset, amount);
            unchecked {
                abs += Sizes.AssetAmount;
            }
        }

        output = Encoder.finish(cur, output);
        return (true, output, value);
    }
    function measureDebitAccount(bytes memory state, bytes calldata input, uint value) external returns (
        uint usedGas, bool handled, bytes memory output, uint credit, uint result
    ) {
        uint beforeGas = gasleft();
        (handled, output, credit) = executeDebitAccount(bytes32(uint(9)), state, input, value);
        usedGas = beforeGas - gasleft();
        result = checksum;
    }
    function executeCreditAccount(
        bytes32 account,
        bytes memory state,
        bytes calldata input,
        uint value
    ) internal returns (bool handled, bytes memory output, uint credit) {
        if (input.length != 0) revert UnexpectedInput();
        (uint abs, uint end) = LegacyMemory.bounds(state, Sizes.Balance);

        while (abs < end) {
            (bytes32 asset, uint amount) = LegacyMemory.unpackBalance(abs);
            creditAccount(account, asset, amount);
            unchecked {
                abs += Sizes.Balance;
            }
        }

        return (true, "", value);
    }
    function measureCreditAccount(bytes memory state, bytes calldata input, uint value) external returns (
        uint usedGas, bool handled, bytes memory output, uint credit, uint result
    ) {
        uint beforeGas = gasleft();
        (handled, output, credit) = executeCreditAccount(bytes32(uint(9)), state, input, value);
        usedGas = beforeGas - gasleft();
        result = checksum;
    }
    function executeCashout(
        bytes32 account,
        bytes memory state,
        bytes calldata input,
        uint value
    ) internal returns (bool handled, bytes memory output, uint credit) {
        if (input.length != 0) revert UnexpectedInput();
        (uint abs, uint end) = LegacyMemory.bounds(state, Sizes.Balance);

        while (abs < end) {
            (bytes32 asset, uint amount) = LegacyMemory.unpackBalance(abs);
            if (asset != chainAsset) revert InvalidAsset();
            cashout(account, amount);
            unchecked {
                abs += Sizes.Balance;
            }
        }

        return (true, "", value);
    }
    function measureCashout(bytes memory state, bytes calldata input, uint value) external returns (
        uint usedGas, bool handled, bytes memory output, uint credit, uint result
    ) {
        uint beforeGas = gasleft();
        (handled, output, credit) = executeCashout(bytes32(uint(9)), state, input, value);
        usedGas = beforeGas - gasleft();
        result = checksum;
    }
    function executeSettle(
        bytes32 account,
        bytes memory state,
        bytes calldata input,
        uint value
    ) internal returns (bool handled, bytes memory output, uint credit) {
        if (input.length != 0) revert UnexpectedInput();
        (uint abs, uint end) = LegacyMemory.bounds(state, Sizes.Position);

        while (abs < end) {
            settle(account, LegacyMemory.unpackPositionValue(abs));
            unchecked {
                abs += Sizes.Position;
            }
        }

        return (true, "", value);
    }
    function measureSettle(bytes memory state, bytes calldata input, uint value) external returns (
        uint usedGas, bool handled, bytes memory output, uint credit, uint result
    ) {
        uint beforeGas = gasleft();
        (handled, output, credit) = executeSettle(bytes32(uint(9)), state, input, value);
        usedGas = beforeGas - gasleft();
        result = checksum;
    }
    function executeAuthorize(
        bytes32 account,
        bytes memory state,
        bytes calldata input,
        uint value
    ) internal returns (bool handled, bytes memory output, uint credit) {
        enforceAdmin(account, address(this));
        if (state.length != 0) revert UnexpectedState();

        (uint abs, uint end) = Cursors.bounds(input, Sizes.B32);
        while (abs < end) {
            authorizeNode(LegacyBlocks.unpackNode(abs));
            unchecked {
                abs += Sizes.B32;
            }
        }

        return (true, "", value);
    }
    function measureAuthorize(bytes memory state, bytes calldata input, uint value) external returns (
        uint usedGas, bool handled, bytes memory output, uint credit, uint result
    ) {
        uint beforeGas = gasleft();
        (handled, output, credit) = executeAuthorize(bytes32(uint(9)), state, input, value);
        usedGas = beforeGas - gasleft();
        result = checksum;
    }
}

contract BlocksMigrationCandidate is MigrationHooks {
    function executeBootstrap(
        bytes32 account,
        bytes memory state,
        bytes calldata input,
        uint value
    ) internal returns (bool handled, bytes memory output, uint credit) {
        if (state.length != 0) revert UnexpectedState();
        uint inputCur = Cursors.wrap(input);
        // floor(input.length / 104) * 72 <= input.length, so multiplication cannot overflow.
        uint cur;
        unchecked {
            (output, cur) = Encoder.init(input.length / 104 * Sizes.Balance);
        }
        credit = value;

        while (Cursors.more(inputCur)) {
            bytes32 asset; uint amount; uint budget;
            bytes32 amountWord; bytes32 budgetWord;
            (asset, amountWord, budgetWord, inputCur) = Blocks.unpack96(inputCur, Keys.Bootstrap);
            amount = uint(amountWord); budget = uint(budgetWord);
            credit = bootstrap(account, asset, amount, budget, credit);
            (output, cur) = Encoder.writeBalance(cur, output, asset, amount);
        }

        output = Encoder.finish(cur, output);
        return (true, output, credit);
    }
    function bootstrap(
        bytes32 account,
        bytes32 asset,
        uint amount,
        uint budget,
        uint value
    ) private returns (uint) {
        if (asset == chainAsset) {
            uint funded = amount < value ? amount : value;
            unchecked {
                amount -= funded;
                value -= funded;
            }
            amount += budget;
        } else {
            if (amount != 0) debitAccount(account, asset, amount);
            amount = budget;
        }

        if (amount != 0) debitAccount(account, chainAsset, amount);
        return value + budget;
    }
    function measureBootstrap(bytes memory state, bytes calldata input, uint value) external returns (
        uint usedGas, bool handled, bytes memory output, uint credit, uint result
    ) {
        uint beforeGas = gasleft();
        (handled, output, credit) = executeBootstrap(bytes32(uint(9)), state, input, value);
        usedGas = beforeGas - gasleft();
        result = checksum;
    }
    function executeDebitAccount(
        bytes32 account,
        bytes memory state,
        bytes calldata input,
        uint value
    ) internal returns (bool handled, bytes memory output, uint credit) {
        if (state.length != 0) revert UnexpectedState();
        uint inputCur = Cursors.wrap(input);
        uint cur;
        (output, cur) = Encoder.init(input.length);

        while (Cursors.more(inputCur)) {
            bytes32 asset;
            uint amount;
            (asset, amount, inputCur) = Blocks.unpackAssetAmount(inputCur);
            debitAccount(account, asset, amount);
            (output, cur) = Encoder.writeBalance(cur, output, asset, amount);
        }

        output = Encoder.finish(cur, output);
        return (true, output, value);
    }
    function measureDebitAccount(bytes memory state, bytes calldata input, uint value) external returns (
        uint usedGas, bool handled, bytes memory output, uint credit, uint result
    ) {
        uint beforeGas = gasleft();
        (handled, output, credit) = executeDebitAccount(bytes32(uint(9)), state, input, value);
        usedGas = beforeGas - gasleft();
        result = checksum;
    }
    function executeCreditAccount(
        bytes32 account,
        bytes memory state,
        bytes calldata input,
        uint value
    ) internal returns (bool handled, bytes memory output, uint credit) {
        if (input.length != 0) revert UnexpectedInput();
        uint stateCur = MemoryBlocks.cursor(state);

        while (MemoryBlocks.more(stateCur)) {
            bytes32 asset;
            uint amount;
            (asset, amount, stateCur) = MemoryBlocks.unpackBalance(stateCur);
            creditAccount(account, asset, amount);
        }

        return (true, "", value);
    }
    function measureCreditAccount(bytes memory state, bytes calldata input, uint value) external returns (
        uint usedGas, bool handled, bytes memory output, uint credit, uint result
    ) {
        uint beforeGas = gasleft();
        (handled, output, credit) = executeCreditAccount(bytes32(uint(9)), state, input, value);
        usedGas = beforeGas - gasleft();
        result = checksum;
    }
    function executeCashout(
        bytes32 account,
        bytes memory state,
        bytes calldata input,
        uint value
    ) internal returns (bool handled, bytes memory output, uint credit) {
        if (input.length != 0) revert UnexpectedInput();
        uint stateCur = MemoryBlocks.cursor(state);

        while (MemoryBlocks.more(stateCur)) {
            bytes32 asset;
            uint amount;
            (asset, amount, stateCur) = MemoryBlocks.unpackBalance(stateCur);
            if (asset != chainAsset) revert InvalidAsset();
            cashout(account, amount);
        }

        return (true, "", value);
    }
    function measureCashout(bytes memory state, bytes calldata input, uint value) external returns (
        uint usedGas, bool handled, bytes memory output, uint credit, uint result
    ) {
        uint beforeGas = gasleft();
        (handled, output, credit) = executeCashout(bytes32(uint(9)), state, input, value);
        usedGas = beforeGas - gasleft();
        result = checksum;
    }
    function executeSettle(
        bytes32 account,
        bytes memory state,
        bytes calldata input,
        uint value
    ) internal returns (bool handled, bytes memory output, uint credit) {
        if (input.length != 0) revert UnexpectedInput();
        uint stateCur = MemoryBlocks.cursor(state);

        while (MemoryBlocks.more(stateCur)) {
            Position memory position;
            (position, stateCur) = MemoryBlocks.unpackPositionValue(stateCur);
            settle(account, position);
        }

        return (true, "", value);
    }
    function measureSettle(bytes memory state, bytes calldata input, uint value) external returns (
        uint usedGas, bool handled, bytes memory output, uint credit, uint result
    ) {
        uint beforeGas = gasleft();
        (handled, output, credit) = executeSettle(bytes32(uint(9)), state, input, value);
        usedGas = beforeGas - gasleft();
        result = checksum;
    }
    function executeAuthorize(
        bytes32 account,
        bytes memory state,
        bytes calldata input,
        uint value
    ) internal returns (bool handled, bytes memory output, uint credit) {
        enforceAdmin(account, address(this));
        if (state.length != 0) revert UnexpectedState();

        uint inputCur = Cursors.wrap(input);
        while (Cursors.more(inputCur)) {
            uint node;
            (node, inputCur) = Blocks.unpackNode(inputCur);
            authorizeNode(node);
        }

        return (true, "", value);
    }
    function measureAuthorize(bytes memory state, bytes calldata input, uint value) external returns (
        uint usedGas, bool handled, bytes memory output, uint credit, uint result
    ) {
        uint beforeGas = gasleft();
        (handled, output, credit) = executeAuthorize(bytes32(uint(9)), state, input, value);
        usedGas = beforeGas - gasleft();
        result = checksum;
    }
}

contract BlocksEncodingMigrationBaseline {
    // Frozen accessor used by this baseline before raw accessors were removed.
    function rawState(Execution memory exec) private pure returns (bytes calldata data) {
        uint cur = exec.state;
        if ((cur & (1 << 64)) == 0) return msg.data[0:0];
        uint current = uint32(cur);
        uint end = uint32(cur >> 32);
        if (end > msg.data.length || current > end) revert MalformedBlocks();
        assembly ("memory-safe") {
            data.offset := current
            data.length := sub(end, current)
        }
    }

    function baselineTakeBalances(Execution memory exec) private pure returns (bytes calldata data) {
        data = rawState(exec);
        // Empty and undeclared lanes require neither scanning nor cursor mutation.
        if (data.length == 0) return data;
        uint abs;
        uint end;
        assembly ("memory-safe") {
            abs := data.offset
            end := add(abs, data.length)
        }
        uint64 expected = LegacyHeaders.Balance;
        while (abs < end) {
            // Check each remaining block before its header, matching unpackBalance's
            // error order even when an earlier bad key precedes a truncated tail.
            unchecked {
                if (end - abs < Sizes.Balance) revert OutOfBounds();
            }
            uint64 head;
            assembly ("memory-safe") {
                head := shr(192, calldataload(abs))
            }
            if (head != expected) revert InvalidBlock();
            unchecked {
                abs += Sizes.Balance;
            }
        }
        uint cur = exec.state;
        exec.state = (cur & ~uint(type(uint32).max)) | end;
    }

    function relayBalances(bytes32 account, bytes calldata state, bytes calldata input) external view
        returns (uint usedGas, bytes memory output, uint remainingState)
    {
        Execution memory exec;
        exec.account = account;
        exec.state = Cursors.wrap(state) | (1 << 64);
        uint inputCur = Cursors.wrap(input);
        uint beforeGas = gasleft();
        bytes calldata steps = Blocks.toBytes(inputCur);
        bytes calldata balances = baselineTakeBalances(exec);
        output = LegacyBlocks.createContextCopy(account, balances, steps);
        usedGas = beforeGas - gasleft();
        remainingState = uint32(exec.state >> 32) - uint32(exec.state);
    }

    function count(bytes calldata source, bytes4 key) external view returns (uint usedGas, uint total) {
        uint cur = Cursors.wrap(source);
        uint beforeGas = gasleft();
        total = LegacyBlocks.runCount(uint32(cur), uint32(cur >> 32), key);
        usedGas = beforeGas - gasleft();
    }
    function context(bytes32 account, bytes calldata state, bytes calldata input) external view returns (uint usedGas, bytes memory output) {
        uint stateCur = Cursors.wrap(state);
        uint inputCur = Cursors.wrap(input);
        uint beforeGas = gasleft();
        output = LegacyBlocks.createContextCopy(account, Blocks.toBytes(stateCur), Blocks.toBytes(inputCur));
        usedGas = beforeGas - gasleft();
    }
    function Action(uint value) external view returns (uint usedGas, bytes memory output) {
        uint beforeGas = gasleft();
        output = LegacyBlocks.createAction(value);
        usedGas = beforeGas - gasleft();
    }
    function Counterparty(bytes32 value) external view returns (uint usedGas, bytes memory output) {
        uint beforeGas = gasleft();
        output = LegacyBlocks.createCounterparty(value);
        usedGas = beforeGas - gasleft();
    }
    function ExecutionCost(uint base, uint batch) external view returns (uint usedGas, bytes memory output) {
        uint beforeGas = gasleft();
        output = LegacyBlocks.createExecutionCost(base, batch);
        usedGas = beforeGas - gasleft();
    }
    function Label(bytes32 namespace, string memory value) external view returns (uint usedGas, bytes memory output) {
        uint beforeGas = gasleft();
        output = LegacyBlocks.createLabel(namespace, value);
        usedGas = beforeGas - gasleft();
    }
    function Schema(uint spec, string memory value) external view returns (uint usedGas, bytes memory output) {
        uint beforeGas = gasleft();
        output = LegacyBlocks.createSchema(spec, value);
        usedGas = beforeGas - gasleft();
    }
}

contract BlocksEncodingMigrationCandidate {

    function relayBalances(bytes32 account, bytes calldata state, bytes calldata input) external view
        returns (uint usedGas, bytes memory output, uint remainingState)
    {
        Execution memory exec;
        exec.account = account;
        exec.state = Cursors.wrap(state);
        uint inputCur = Cursors.wrap(input);
        uint beforeGas = gasleft();
        uint stateCur = Executions.takeBalances(exec);
        output = Encoder.createContext(account, stateCur, inputCur);
        usedGas = beforeGas - gasleft();
        remainingState = uint32(exec.state >> 32) - uint32(exec.state);
    }

    function count(bytes calldata source, bytes4 key) external view returns (uint usedGas, uint total) {
        uint cur = Cursors.wrap(source);
        uint beforeGas = gasleft();
        total = Blocks.runCount(cur, key);
        usedGas = beforeGas - gasleft();
    }
    function context(bytes32 account, bytes calldata state, bytes calldata input) external view returns (uint usedGas, bytes memory output) {
        uint stateCur = Cursors.wrap(state);
        uint inputCur = Cursors.wrap(input);
        uint beforeGas = gasleft();
        output = Encoder.createContext(account, stateCur, inputCur);
        usedGas = beforeGas - gasleft();
    }
    function Action(uint value) external view returns (uint usedGas, bytes memory output) {
        uint beforeGas = gasleft();
        output = LegacyBlocks.createAction(value);

        usedGas = beforeGas - gasleft();
    }
    function Counterparty(bytes32 value) external view returns (uint usedGas, bytes memory output) {
        uint beforeGas = gasleft();
        output = Encoder.createCounterparty(value);

        usedGas = beforeGas - gasleft();
    }
    function ExecutionCost(uint base, uint batch) external view returns (uint usedGas, bytes memory output) {
        uint beforeGas = gasleft();
        output = PreviousExecutionCost.createExecutionCost(base, batch);
        usedGas = beforeGas - gasleft();
    }
    function Label(bytes32 namespace, string memory value) external view returns (uint usedGas, bytes memory output) {
        uint beforeGas = gasleft();
        output = PreviousNamingEncoder.createLabel(namespace, bytes(value));
        usedGas = beforeGas - gasleft();
    }
    function Schema(uint spec, string memory value) external view returns (uint usedGas, bytes memory output) {
        uint beforeGas = gasleft();
        output = Encoder.createSchema(spec, bytes(value));
        usedGas = beforeGas - gasleft();
    }
}

contract TestTakeBalances {
    function takeBalanceState(bytes calldata source, uint offset, uint endOffset)
        external pure returns (uint selected, uint beforeCur, uint afterCur, uint input)
    {
        uint abs;
        assembly ("memory-safe") { abs := source.offset }
        Execution memory exec;
        exec.input = 123;
        exec.state = (abs + offset) | ((abs + endOffset) << 32);
        beforeCur = exec.state;
        selected = Executions.takeBalances(exec);
        return (selected, beforeCur, exec.state, exec.input);
    }

}
