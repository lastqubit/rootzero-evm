// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;
import {Logs as PreviousLogs} from "./PreviousEventLogs.sol";
import {LegacyBlocks} from "./LegacyBlocks.sol";
import {PreviousSpecs as HistoricalSpecs} from "./PreviousSpecs.sol";
import {Logs} from "../codec/Logs.sol";
import {PreviousOutputBootstrap, PreviousOutputDebitAccount} from "./PreviousExecuteOutput.sol";
import {ExecuteBootstrap} from "../commands/Bootstrap.sol";
import {ExecuteDebitAccount, DebitAccount} from "../commands/Debit.sol";
import {CommandBase} from "../commands/Base.sol";
import {Encoder} from "../codec/Encoder.sol";
import {Execute} from "../codec/Execute.sol";
import {Keys} from "../codec/Keys.sol";
import {Sizes, Specs} from "../codec/Specs.sol";
import {Cursors} from "../utils/Cursors.sol";
import {UnexpectedState} from "../utils/Errors.sol";
import {DebitAccountHook} from "../core/Settlement.sol";
import {Runtime} from "../core/Runtime.sol";

// Benchmark-only writer alternatives. All callers prove the complete output
// size once, write every logical byte, and never expose an unwritten buffer.
abstract contract PreallocatedWriter {
    function initOutput(uint size) internal pure virtual returns (uint cur, bytes memory dst);
    function writeBalanceOutput(uint cur, bytes memory dst, bytes32 asset, uint amount) internal pure virtual returns (uint nextCur);
    function finishOutput(uint cur, bytes memory dst) internal pure virtual returns (bytes memory);
    function writeBalanceAt(uint abs, bytes32 asset, uint amount) internal pure returns (uint) {
        abs = Encoder.writeHeader(abs, Keys.Balance, 64);
        abs = Encoder.write32(abs, asset);
        return Encoder.write32(abs, bytes32(amount));
    }
}

abstract contract ReserveOnceWriter is PreallocatedWriter {
    function initOutput(uint size) internal pure override returns (uint abs, bytes memory dst) {
        uint cur;
        (dst, cur) = Encoder.init(size);
        (dst, abs, ) = Encoder.reserve(cur, dst, size);
    }
    function writeBalanceOutput(uint abs, bytes memory, bytes32 asset, uint amount) internal pure override returns (uint) {
        return writeBalanceAt(abs, asset, amount);
    }
    function finishOutput(uint abs, bytes memory dst) internal pure override returns (bytes memory) {
        return Encoder.finish(abs - Encoder.pos(dst, 0), dst);
    }
}

// Frozen exact-allocation prototype, kept for comparison with the production
// Execute count-based allocation and reserved-memory writer.
abstract contract ExactWriter is PreallocatedWriter {
    function initOutput(uint size) internal pure override returns (uint abs, bytes memory dst) {
        dst = Encoder.allocate(size);
        abs = Encoder.pos(dst, 0);
    }
    function writeBalanceOutput(uint abs, bytes memory, bytes32 asset, uint amount) internal pure override returns (uint) {
        return writeBalanceAt(abs, asset, amount);
    }
    function finishOutput(uint, bytes memory dst) internal pure override returns (bytes memory) {
        return dst;
    }
}

abstract contract UncheckedCursorWriter is PreallocatedWriter {
    function initOutput(uint size) internal pure override returns (uint cur, bytes memory dst) {
        (dst, cur) = Encoder.init(size);
    }
    function writeBalanceOutput(uint cur, bytes memory dst, bytes32 asset, uint amount) internal pure override returns (uint nextCur) {
        writeBalanceAt(Encoder.pos(dst, uint32(cur)), asset, amount);
        unchecked { nextCur = cur + 72; }
    }
    function finishOutput(uint cur, bytes memory dst) internal pure override returns (bytes memory) {
        return Encoder.finish(cur, dst);
    }
}

abstract contract PreallocatedBootstrap is PreallocatedWriter, CommandBase, DebitAccountHook {
    uint private immutable id;

    constructor() {
        (id,) = command("bootstrap", Specs.Empty, HistoricalSpecs.Bootstrap, Specs.Balance, 0);
    }

    /// @notice Return the registered BOOTSTRAP command ID.
    function bootstrapId() internal view returns (uint) {
        return id;
    }

    /// @dev Bootstrap one local balance, using assigned value before debiting
    /// any remaining chain-asset amount from the account.
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

    /// @notice Execute bootstrap directly against a calldata BOOTSTRAP stream.
    /// @param account Account funding the pipeline.
    /// @param state Empty pipeline state required by the command schema.
    /// @param inputCur Cursor over BOOTSTRAP block stream.
    /// @param value Native value available to fund chain-asset balances.
    /// @return handled Always true because this helper executed the command.
    /// @return output One BALANCE block per BOOTSTRAP input.
    /// @return credit Sourced budget contributions plus unused assigned value.
    function executeBootstrap(
        bytes32 account,
        bytes memory state,
        uint inputCur,
        uint value
    ) internal returns (bool handled, bytes memory output, uint credit) {
        if (state.length != 0) revert UnexpectedState();
        (uint abs, uint end) = Execute.bounds(inputCur, 104);
        // floor(input.length / 104) * 72 <= input.length, so multiplication cannot overflow.
        uint cur;
        unchecked {
            (cur, output) = initOutput((end - abs) / 104 * Sizes.Balance);
        }
        credit = value;

        while (abs < end) {
            (bytes32 asset, uint amount, uint budget) = LegacyBlocks.unpackBootstrap(abs);
            credit = bootstrap(account, asset, amount, budget, credit);
            cur = writeBalanceOutput(cur, output, asset, amount);
            unchecked {
                abs += 104;
            }
        }

        output = finishOutput(cur, output);
        return (true, output, credit);
    }
}

abstract contract PreallocatedDebitAccount is PreallocatedWriter, DebitAccount {
    /// @notice Execute the inherited debit-account command from an internal pipeline.
    /// @param account Account whose funds are debited.
    /// @param state Empty pipeline state required by the command schema.
    /// @param inputCur ASSET_AMOUNT block stream.
    /// @param value Native value assigned to the command; returned unused as credit.
    /// @return handled Always true because this helper executed the command.
    /// @return output BALANCE block stream matching the debited amounts.
    /// @return credit Unused assigned native value.
    function executeDebitAccount(
        bytes32 account,
        bytes memory state,
        uint inputCur,
        uint value
    ) internal returns (bool handled, bytes memory output, uint credit) {
        if (state.length != 0) revert UnexpectedState();
        (uint abs, uint end) = Execute.bounds(inputCur, Sizes.AssetAmount);
        uint cur;
        (cur, output) = initOutput(end - abs);

        while (abs < end) {
            (bytes32 asset, uint amount) = Execute.unpackAssetAmount(abs);
            debitAccount(account, asset, amount);
            cur = writeBalanceOutput(cur, output, asset, amount);
            unchecked {
                abs += Sizes.AssetAmount;
            }
        }

        output = finishOutput(cur, output);
        PreviousLogs.memWrap(debitAccountId(), Keys.Output, output);
        return (true, output, value);
    }
}

contract ExecuteOutputBaseline is PreviousOutputBootstrap, PreviousOutputDebitAccount {
    uint public checksum;
    bool public allocateInHook;
    constructor() Runtime(0, address(0)) {}
    function nativeAsset() external view returns (bytes32) { return chainAsset; }
    function setAllocate(bool enabled) external { allocateInHook = enabled; }
    function enforceCaller(address caller) internal pure override returns (address) { return caller; }
    function debitAccount(bytes32 account, bytes32 asset, uint amount) internal override {
        require(amount != type(uint).max, "hook");
        unchecked { checksum += uint(account) ^ uint(asset) ^ amount; }
        if (allocateInHook) {
            bytes memory scratch = new bytes(97);
            assembly ("memory-safe") {
                mstore(add(scratch, 32), not(0))
                mstore(add(scratch, 64), not(0))
                mstore(add(scratch, 96), not(0))
            }
            checksum ^= uint(keccak256(scratch));
        }
    }

    function measureBootstrap(bytes memory state, bytes calldata input, uint value) external returns (
        uint usedGas, uint allocated, bytes memory output, uint credit, uint result
    ) {
        uint inputCur = Cursors.wrap(input);
        uint free;
        assembly ("memory-safe") { free := mload(0x40) }
        uint initial = gasleft();
        (, output, credit) = executeBootstrap(bytes32(uint(9)), state, inputCur, value);
        usedGas = initial - gasleft();
        assembly ("memory-safe") { allocated := sub(mload(0x40), free) }
        result = checksum;
        // Later allocations must not corrupt output or its ABI padding.
        bytes32 digest = keccak256(output);
        bytes memory later = new bytes(97);
        assembly ("memory-safe") { mstore(add(later, 32), not(0)) }
        require(digest == keccak256(output));
    }

    function measureDebitAccount(bytes memory state, bytes calldata input, uint value) external returns (
        uint usedGas, uint allocated, bytes memory output, uint credit, uint result
    ) {
        uint inputCur = Cursors.wrap(input);
        uint free;
        assembly ("memory-safe") { free := mload(0x40) }
        uint initial = gasleft();
        (, output, credit) = executeDebitAccount(bytes32(uint(9)), state, inputCur, value);
        usedGas = initial - gasleft();
        assembly ("memory-safe") { allocated := sub(mload(0x40), free) }
        result = checksum;
        // Later allocations must not corrupt output or its ABI padding.
        bytes32 digest = keccak256(output);
        bytes memory later = new bytes(97);
        assembly ("memory-safe") { mstore(add(later, 32), not(0)) }
        require(digest == keccak256(output));
    }
}

contract ExecuteOutputReserved is PreallocatedBootstrap, PreallocatedDebitAccount, ReserveOnceWriter {
    uint public checksum;
    bool public allocateInHook;
    constructor() Runtime(0, address(0)) {}
    function nativeAsset() external view returns (bytes32) { return chainAsset; }
    function setAllocate(bool enabled) external { allocateInHook = enabled; }
    function enforceCaller(address caller) internal pure override returns (address) { return caller; }
    function debitAccount(bytes32 account, bytes32 asset, uint amount) internal override {
        require(amount != type(uint).max, "hook");
        unchecked { checksum += uint(account) ^ uint(asset) ^ amount; }
        if (allocateInHook) {
            bytes memory scratch = new bytes(97);
            assembly ("memory-safe") {
                mstore(add(scratch, 32), not(0))
                mstore(add(scratch, 64), not(0))
                mstore(add(scratch, 96), not(0))
            }
            checksum ^= uint(keccak256(scratch));
        }
    }

    function measureBootstrap(bytes memory state, bytes calldata input, uint value) external returns (
        uint usedGas, uint allocated, bytes memory output, uint credit, uint result
    ) {
        uint inputCur = Cursors.wrap(input);
        uint free;
        assembly ("memory-safe") { free := mload(0x40) }
        uint initial = gasleft();
        (, output, credit) = executeBootstrap(bytes32(uint(9)), state, inputCur, value);
        usedGas = initial - gasleft();
        assembly ("memory-safe") { allocated := sub(mload(0x40), free) }
        result = checksum;
        // Later allocations must not corrupt output or its ABI padding.
        bytes32 digest = keccak256(output);
        bytes memory later = new bytes(97);
        assembly ("memory-safe") { mstore(add(later, 32), not(0)) }
        require(digest == keccak256(output));
    }

    function measureDebitAccount(bytes memory state, bytes calldata input, uint value) external returns (
        uint usedGas, uint allocated, bytes memory output, uint credit, uint result
    ) {
        uint inputCur = Cursors.wrap(input);
        uint free;
        assembly ("memory-safe") { free := mload(0x40) }
        uint initial = gasleft();
        (, output, credit) = executeDebitAccount(bytes32(uint(9)), state, inputCur, value);
        usedGas = initial - gasleft();
        assembly ("memory-safe") { allocated := sub(mload(0x40), free) }
        result = checksum;
        // Later allocations must not corrupt output or its ABI padding.
        bytes32 digest = keccak256(output);
        bytes memory later = new bytes(97);
        assembly ("memory-safe") { mstore(add(later, 32), not(0)) }
        require(digest == keccak256(output));
    }
}

contract ExecuteOutputExact is PreallocatedBootstrap, PreallocatedDebitAccount, ExactWriter {
    uint public checksum;
    bool public allocateInHook;
    constructor() Runtime(0, address(0)) {}
    function nativeAsset() external view returns (bytes32) { return chainAsset; }
    function setAllocate(bool enabled) external { allocateInHook = enabled; }
    function enforceCaller(address caller) internal pure override returns (address) { return caller; }
    function debitAccount(bytes32 account, bytes32 asset, uint amount) internal override {
        require(amount != type(uint).max, "hook");
        unchecked { checksum += uint(account) ^ uint(asset) ^ amount; }
        if (allocateInHook) {
            bytes memory scratch = new bytes(97);
            assembly ("memory-safe") {
                mstore(add(scratch, 32), not(0))
                mstore(add(scratch, 64), not(0))
                mstore(add(scratch, 96), not(0))
            }
            checksum ^= uint(keccak256(scratch));
        }
    }

    function measureBootstrap(bytes memory state, bytes calldata input, uint value) external returns (
        uint usedGas, uint allocated, bytes memory output, uint credit, uint result
    ) {
        uint inputCur = Cursors.wrap(input);
        uint free;
        assembly ("memory-safe") { free := mload(0x40) }
        uint initial = gasleft();
        (, output, credit) = executeBootstrap(bytes32(uint(9)), state, inputCur, value);
        usedGas = initial - gasleft();
        assembly ("memory-safe") { allocated := sub(mload(0x40), free) }
        result = checksum;
        // Later allocations must not corrupt output or its ABI padding.
        bytes32 digest = keccak256(output);
        bytes memory later = new bytes(97);
        assembly ("memory-safe") { mstore(add(later, 32), not(0)) }
        require(digest == keccak256(output));
    }

    function measureDebitAccount(bytes memory state, bytes calldata input, uint value) external returns (
        uint usedGas, uint allocated, bytes memory output, uint credit, uint result
    ) {
        uint inputCur = Cursors.wrap(input);
        uint free;
        assembly ("memory-safe") { free := mload(0x40) }
        uint initial = gasleft();
        (, output, credit) = executeDebitAccount(bytes32(uint(9)), state, inputCur, value);
        usedGas = initial - gasleft();
        assembly ("memory-safe") { allocated := sub(mload(0x40), free) }
        result = checksum;
        // Later allocations must not corrupt output or its ABI padding.
        bytes32 digest = keccak256(output);
        bytes memory later = new bytes(97);
        assembly ("memory-safe") { mstore(add(later, 32), not(0)) }
        require(digest == keccak256(output));
    }
}

contract ExecuteOutputUnchecked is PreallocatedBootstrap, PreallocatedDebitAccount, UncheckedCursorWriter {
    uint public checksum;
    bool public allocateInHook;
    constructor() Runtime(0, address(0)) {}
    function nativeAsset() external view returns (bytes32) { return chainAsset; }
    function setAllocate(bool enabled) external { allocateInHook = enabled; }
    function enforceCaller(address caller) internal pure override returns (address) { return caller; }
    function debitAccount(bytes32 account, bytes32 asset, uint amount) internal override {
        require(amount != type(uint).max, "hook");
        unchecked { checksum += uint(account) ^ uint(asset) ^ amount; }
        if (allocateInHook) {
            bytes memory scratch = new bytes(97);
            assembly ("memory-safe") {
                mstore(add(scratch, 32), not(0))
                mstore(add(scratch, 64), not(0))
                mstore(add(scratch, 96), not(0))
            }
            checksum ^= uint(keccak256(scratch));
        }
    }

    function measureBootstrap(bytes memory state, bytes calldata input, uint value) external returns (
        uint usedGas, uint allocated, bytes memory output, uint credit, uint result
    ) {
        uint inputCur = Cursors.wrap(input);
        uint free;
        assembly ("memory-safe") { free := mload(0x40) }
        uint initial = gasleft();
        (, output, credit) = executeBootstrap(bytes32(uint(9)), state, inputCur, value);
        usedGas = initial - gasleft();
        assembly ("memory-safe") { allocated := sub(mload(0x40), free) }
        result = checksum;
        // Later allocations must not corrupt output or its ABI padding.
        bytes32 digest = keccak256(output);
        bytes memory later = new bytes(97);
        assembly ("memory-safe") { mstore(add(later, 32), not(0)) }
        require(digest == keccak256(output));
    }

    function measureDebitAccount(bytes memory state, bytes calldata input, uint value) external returns (
        uint usedGas, uint allocated, bytes memory output, uint credit, uint result
    ) {
        uint inputCur = Cursors.wrap(input);
        uint free;
        assembly ("memory-safe") { free := mload(0x40) }
        uint initial = gasleft();
        (, output, credit) = executeDebitAccount(bytes32(uint(9)), state, inputCur, value);
        usedGas = initial - gasleft();
        assembly ("memory-safe") { allocated := sub(mload(0x40), free) }
        result = checksum;
        // Later allocations must not corrupt output or its ABI padding.
        bytes32 digest = keccak256(output);
        bytes memory later = new bytes(97);
        assembly ("memory-safe") { mstore(add(later, 32), not(0)) }
        require(digest == keccak256(output));
    }
}

contract ExecuteOutputCurrent is ExecuteBootstrap, ExecuteDebitAccount {
    uint public checksum;
    bool public allocateInHook;
    constructor() Runtime(0, address(0)) {}
    function nativeAsset() external view returns (bytes32) { return chainAsset; }
    function setAllocate(bool enabled) external { allocateInHook = enabled; }
    function enforceCaller(address caller) internal pure override returns (address) { return caller; }
    function debitAccount(bytes32 account, bytes32 asset, uint amount) internal override {
        require(amount != type(uint).max, "hook");
        unchecked { checksum += uint(account) ^ uint(asset) ^ amount; }
        if (allocateInHook) {
            bytes memory scratch = new bytes(97);
            assembly ("memory-safe") {
                mstore(add(scratch, 32), not(0))
                mstore(add(scratch, 64), not(0))
                mstore(add(scratch, 96), not(0))
            }
            checksum ^= uint(keccak256(scratch));
        }
    }

    function measureBootstrap(bytes memory state, bytes calldata input, uint value) external returns (
        uint usedGas, uint allocated, bytes memory output, uint credit, uint result
    ) {
        uint inputCur = Cursors.wrap(input);
        uint free;
        assembly ("memory-safe") { free := mload(0x40) }
        uint initial = gasleft();
        (, output, credit) = executeBootstrap(bytes32(uint(9)), state, inputCur, value);
        usedGas = initial - gasleft();
        assembly ("memory-safe") { allocated := sub(mload(0x40), free) }
        result = checksum;
        // Later allocations must not corrupt output or its ABI padding.
        bytes32 digest = keccak256(output);
        bytes memory later = new bytes(97);
        assembly ("memory-safe") { mstore(add(later, 32), not(0)) }
        require(digest == keccak256(output));
    }

    function measureDebitAccount(bytes memory state, bytes calldata input, uint value) external returns (
        uint usedGas, uint allocated, bytes memory output, uint credit, uint result
    ) {
        uint inputCur = Cursors.wrap(input);
        uint free;
        assembly ("memory-safe") { free := mload(0x40) }
        uint initial = gasleft();
        (, output, credit) = executeDebitAccount(bytes32(uint(9)), state, inputCur, value);
        usedGas = initial - gasleft();
        assembly ("memory-safe") { allocated := sub(mload(0x40), free) }
        result = checksum;
        // Later allocations must not corrupt output or its ABI padding.
        bytes32 digest = keccak256(output);
        bytes memory later = new bytes(97);
        assembly ("memory-safe") { mstore(add(later, 32), not(0)) }
        require(digest == keccak256(output));
    }
}
