// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;
import {Cursors} from "../utils/Cursors.sol";
import {Position} from "../core/Types.sol";
import {Runtime} from "../core/Runtime.sol";
import {ExecuteBootstrap} from "../commands/Bootstrap.sol";
import {ExecuteDebitAccount} from "../commands/Debit.sol";
import {ExecuteCreditAccount} from "../commands/Credit.sol";
import {ExecuteCashout} from "../commands/Cashout.sol";
import {ExecuteSettle} from "../commands/Settle.sol";
import {ExecuteAuthorize} from "../commands/admin/Authorize.sol";
import {ExecuteCheckBalance} from "../commands/Balance.sol";
import {ExecuteCheckPosition} from "../commands/Position.sol";
import {PreviousExecuteBootstrap, PreviousExecuteDebitAccount, PreviousExecuteCreditAccount, PreviousExecuteCashout, PreviousExecuteSettle, PreviousExecuteAuthorize, PreviousExecuteCheckBalance, PreviousExecuteCheckPosition} from "./PreviousExecuteAdapters.sol";

contract ExecuteAdaptersBaseline is PreviousExecuteBootstrap, PreviousExecuteDebitAccount, PreviousExecuteCreditAccount, PreviousExecuteCashout, PreviousExecuteSettle, PreviousExecuteAuthorize, PreviousExecuteCheckBalance, PreviousExecuteCheckPosition {
    uint public checksum;
    constructor() Runtime(0) {}
    function nativeAsset() external view returns (bytes32) { return chainAsset; }
    function enforceCaller(address caller) internal pure override returns (address) { return caller; }
    function enforcePeer(address caller) internal pure override returns (address) { return caller; }
    function enforceAdmin(bytes32 account, address) internal pure override returns (bytes32) { require(account == bytes32(uint(9))); return account; }
    function enforceCommand(uint) internal pure override returns (bytes4, address) { return (bytes4(0), address(0)); }
    function enforcePort(uint) internal pure override returns (bytes4, address) { return (bytes4(0), address(0)); }
    function setAccess(uint node, bool enabled) internal override { if (enabled) { unchecked { checksum += node; } } }
    function debitAccount(bytes32 account, bytes32 asset, uint amount) internal override {
        require(amount != type(uint).max, "hook");
        unchecked { checksum += uint(account) ^ uint(asset) ^ amount; }
    }
    function creditAccount(bytes32 account, bytes32 asset, uint amount) internal override { debitAccount(account, asset, amount); }
    function cashout(bytes32 account, uint amount) internal override { debitAccount(account, chainAsset, amount); }
    function settle(bytes32 account, Position memory position) internal override {
        require(position.amount != type(uint).max, "hook");
        unchecked { checksum += uint(account) ^ uint(position.asset) ^ position.amount ^ uint(position.liability) ^ position.debt ^ uint(position.counterparty); }
        position.amount = 0;
    }

    function measureBootstrap(bytes memory state, bytes calldata input, uint value) external returns (
        uint usedGas, bool handled, bytes memory output, uint credit, uint result, bytes32 stateHash
    ) {
        uint inputCur = Cursors.wrap(input);
        uint initial = gasleft();
        (handled, output, credit) = executeBootstrap(bytes32(uint(9)), state, inputCur, value);
        usedGas = initial - gasleft();
        result = checksum;
        stateHash = keccak256(state);
    }

    function measureDebitAccount(bytes memory state, bytes calldata input, uint value) external returns (
        uint usedGas, bool handled, bytes memory output, uint credit, uint result, bytes32 stateHash
    ) {
        uint inputCur = Cursors.wrap(input);
        uint initial = gasleft();
        (handled, output, credit) = executeDebitAccount(bytes32(uint(9)), state, inputCur, value);
        usedGas = initial - gasleft();
        result = checksum;
        stateHash = keccak256(state);
    }

    function measureCreditAccount(bytes memory state, bytes calldata input, uint value) external returns (
        uint usedGas, bool handled, bytes memory output, uint credit, uint result, bytes32 stateHash
    ) {
        uint inputCur = Cursors.wrap(input);
        uint initial = gasleft();
        (handled, output, credit) = executeCreditAccount(bytes32(uint(9)), state, inputCur, value);
        usedGas = initial - gasleft();
        result = checksum;
        stateHash = keccak256(state);
    }

    function measureCashout(bytes memory state, bytes calldata input, uint value) external returns (
        uint usedGas, bool handled, bytes memory output, uint credit, uint result, bytes32 stateHash
    ) {
        uint inputCur = Cursors.wrap(input);
        uint initial = gasleft();
        (handled, output, credit) = executeCashout(bytes32(uint(9)), state, inputCur, value);
        usedGas = initial - gasleft();
        result = checksum;
        stateHash = keccak256(state);
    }

    function measureSettle(bytes memory state, bytes calldata input, uint value) external returns (
        uint usedGas, bool handled, bytes memory output, uint credit, uint result, bytes32 stateHash
    ) {
        uint inputCur = Cursors.wrap(input);
        uint initial = gasleft();
        (handled, output, credit) = executeSettle(bytes32(uint(9)), state, inputCur, value);
        usedGas = initial - gasleft();
        result = checksum;
        stateHash = keccak256(state);
    }

    function measureAuthorize(bytes memory state, bytes calldata input, uint value) external returns (
        uint usedGas, bool handled, bytes memory output, uint credit, uint result, bytes32 stateHash
    ) {
        uint inputCur = Cursors.wrap(input);
        uint initial = gasleft();
        (handled, output, credit) = executeAuthorize(bytes32(uint(9)), state, inputCur, value);
        usedGas = initial - gasleft();
        result = checksum;
        stateHash = keccak256(state);
    }

    function measureCheckBalance(bytes memory state, bytes calldata input, uint value) external returns (
        uint usedGas, bool handled, bytes memory output, uint credit, uint result, bytes32 stateHash
    ) {
        uint inputCur = Cursors.wrap(input);
        uint initial = gasleft();
        (handled, output, credit) = executeCheckBalance(bytes32(uint(9)), state, inputCur, value);
        usedGas = initial - gasleft();
        result = checksum;
        stateHash = keccak256(state);
    }

    function measureCheckPosition(bytes memory state, bytes calldata input, uint value) external returns (
        uint usedGas, bool handled, bytes memory output, uint credit, uint result, bytes32 stateHash
    ) {
        uint inputCur = Cursors.wrap(input);
        uint initial = gasleft();
        (handled, output, credit) = executeCheckPosition(bytes32(uint(9)), state, inputCur, value);
        usedGas = initial - gasleft();
        result = checksum;
        stateHash = keccak256(state);
    }
}

contract ExecuteAdaptersCurrent is ExecuteBootstrap, ExecuteDebitAccount, ExecuteCreditAccount, ExecuteCashout, ExecuteSettle, ExecuteAuthorize, ExecuteCheckBalance, ExecuteCheckPosition {
    uint public checksum;
    constructor() Runtime(0) {}
    function nativeAsset() external view returns (bytes32) { return chainAsset; }
    function enforceCaller(address caller) internal pure override returns (address) { return caller; }
    function enforcePeer(address caller) internal pure override returns (address) { return caller; }
    function enforceAdmin(bytes32 account, address) internal pure override returns (bytes32) { require(account == bytes32(uint(9))); return account; }
    function enforceCommand(uint) internal pure override returns (bytes4, address) { return (bytes4(0), address(0)); }
    function enforcePort(uint) internal pure override returns (bytes4, address) { return (bytes4(0), address(0)); }
    function setAccess(uint node, bool enabled) internal override { if (enabled) { unchecked { checksum += node; } } }
    function debitAccount(bytes32 account, bytes32 asset, uint amount) internal override {
        require(amount != type(uint).max, "hook");
        unchecked { checksum += uint(account) ^ uint(asset) ^ amount; }
    }
    function creditAccount(bytes32 account, bytes32 asset, uint amount) internal override { debitAccount(account, asset, amount); }
    function cashout(bytes32 account, uint amount) internal override { debitAccount(account, chainAsset, amount); }
    function settle(bytes32 account, Position memory position) internal override {
        require(position.amount != type(uint).max, "hook");
        unchecked { checksum += uint(account) ^ uint(position.asset) ^ position.amount ^ uint(position.liability) ^ position.debt ^ uint(position.counterparty); }
        position.amount = 0;
    }

    function measureBootstrap(bytes memory state, bytes calldata input, uint value) external returns (
        uint usedGas, bool handled, bytes memory output, uint credit, uint result, bytes32 stateHash
    ) {
        uint inputCur = Cursors.wrap(input);
        uint initial = gasleft();
        (handled, output, credit) = executeBootstrap(bytes32(uint(9)), state, inputCur, value);
        usedGas = initial - gasleft();
        result = checksum;
        stateHash = keccak256(state);
    }

    function measureDebitAccount(bytes memory state, bytes calldata input, uint value) external returns (
        uint usedGas, bool handled, bytes memory output, uint credit, uint result, bytes32 stateHash
    ) {
        uint inputCur = Cursors.wrap(input);
        uint initial = gasleft();
        (handled, output, credit) = executeDebitAccount(bytes32(uint(9)), state, inputCur, value);
        usedGas = initial - gasleft();
        result = checksum;
        stateHash = keccak256(state);
    }

    function measureCreditAccount(bytes memory state, bytes calldata input, uint value) external returns (
        uint usedGas, bool handled, bytes memory output, uint credit, uint result, bytes32 stateHash
    ) {
        uint inputCur = Cursors.wrap(input);
        uint initial = gasleft();
        (handled, output, credit) = executeCreditAccount(bytes32(uint(9)), state, inputCur, value);
        usedGas = initial - gasleft();
        result = checksum;
        stateHash = keccak256(state);
    }

    function measureCashout(bytes memory state, bytes calldata input, uint value) external returns (
        uint usedGas, bool handled, bytes memory output, uint credit, uint result, bytes32 stateHash
    ) {
        uint inputCur = Cursors.wrap(input);
        uint initial = gasleft();
        (handled, output, credit) = executeCashout(bytes32(uint(9)), state, inputCur, value);
        usedGas = initial - gasleft();
        result = checksum;
        stateHash = keccak256(state);
    }

    function measureSettle(bytes memory state, bytes calldata input, uint value) external returns (
        uint usedGas, bool handled, bytes memory output, uint credit, uint result, bytes32 stateHash
    ) {
        uint inputCur = Cursors.wrap(input);
        uint initial = gasleft();
        (handled, output, credit) = executeSettle(bytes32(uint(9)), state, inputCur, value);
        usedGas = initial - gasleft();
        result = checksum;
        stateHash = keccak256(state);
    }

    function measureAuthorize(bytes memory state, bytes calldata input, uint value) external returns (
        uint usedGas, bool handled, bytes memory output, uint credit, uint result, bytes32 stateHash
    ) {
        uint inputCur = Cursors.wrap(input);
        uint initial = gasleft();
        (handled, output, credit) = executeAuthorize(bytes32(uint(9)), state, inputCur, value);
        usedGas = initial - gasleft();
        result = checksum;
        stateHash = keccak256(state);
    }

    function measureCheckBalance(bytes memory state, bytes calldata input, uint value) external returns (
        uint usedGas, bool handled, bytes memory output, uint credit, uint result, bytes32 stateHash
    ) {
        uint inputCur = Cursors.wrap(input);
        uint initial = gasleft();
        (handled, output, credit) = executeCheckBalance(bytes32(uint(9)), state, inputCur, value);
        usedGas = initial - gasleft();
        result = checksum;
        stateHash = keccak256(state);
    }

    function measureCheckPosition(bytes memory state, bytes calldata input, uint value) external returns (
        uint usedGas, bool handled, bytes memory output, uint credit, uint result, bytes32 stateHash
    ) {
        uint inputCur = Cursors.wrap(input);
        uint initial = gasleft();
        (handled, output, credit) = executeCheckPosition(bytes32(uint(9)), state, inputCur, value);
        usedGas = initial - gasleft();
        result = checksum;
        stateHash = keccak256(state);
    }
}
