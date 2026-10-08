// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;
import {Logs as PreviousLogs} from "./PreviousEventLogs.sol";
import {Actions} from "./PreviousActions.sol";

import {LogsBalance151} from "./LogsBalance151.sol";

import {BootstrapLogged151} from "./BootstrapLogged151.sol";
import {ExecuteBootstrap} from "../commands/Bootstrap.sol";
import {BootstrapStock150} from "./BootstrapStock150.sol";
import {BootstrapZero150} from "./BootstrapZero150.sol";
import {LogsStock150} from "./LogsStock150.sol";
import {CommandBase} from "../commands/Base.sol";
import {CommanderBootstrapLedger} from "./TestCommanderBootstrapComparison.sol";
import {DebitAccountHook} from "../core/Settlement.sol";
import {Runtime} from "../core/Runtime.sol";
import {Cursors, Logs, Keys} from "../Codec.sol";
import {Entities} from "./PreviousEntities.sol";

/// @dev Identical ledger and transport harness for all candidates. Frozen variants
/// differ only in Bootstrap and scalar logging. No external token transfers.
abstract contract BootstrapShortHarness is CommandBase, DebitAccountHook, CommanderBootstrapLedger {
    bool public allocateHooks;
    uint public hookCalls;

    function enforceCaller(address caller) internal pure override returns (address) { return caller; }
    function nativeAsset() external view returns (bytes32) { return chainAsset; }
    function setAllocate(bool enabled) external { allocateHooks = enabled; }
    function fund(bytes32 account) external payable { balances[account][chainAsset] += msg.value; }

    function debitAccount(bytes32 account, bytes32 asset, uint amount) internal override {
        require(amount != 0, "zero hook");
        ++hookCalls;
        debitFrom(account, asset, amount);
        if (allocateHooks) {
            bytes memory scratch = new bytes(97);
            assembly ("memory-safe") {
                mstore(add(scratch, 32), not(0))
                mstore(add(scratch, 64), not(0))
                mstore(add(scratch, 96), not(0))
            }
            require(scratch[0] == 0xff);
        }
    }

    function bootstrap(bytes memory state, uint cur, uint value)
        internal virtual returns (bytes memory output, uint credit);
    function logPipeline(uint value) internal virtual;
    function logBalance(uint value) internal virtual;

    /// @dev msg.sender is the only account in this fixture. Returned balances are
    /// credited back, then remaining native value is credited like Commander cashin.
    function run(bytes calldata input) external payable returns (uint used, bytes memory output, uint credit) {
        bytes32 account = bytes32(uint(uint160(msg.sender)));
        bytes memory sentinel = new bytes(97);
        bytes32 digest = keccak256(sentinel);
        // Dirty temporary memory proves padding does not rely on fresh EVM zeros.
        if (allocateHooks) {
            assembly ("memory-safe") {
                let f := mload(0x40)
                for { let p := f } lt(p, add(f, 4096)) { p := add(p, 32) } { mstore(p, not(0)) }
            }
        }
        bytes memory empty;
        uint start = gasleft();
        logPipeline(msg.value);
        (output, credit) = bootstrap(empty, Cursors.wrap(input), msg.value);
        // Inspect the logical output tail, not only ABI re-encoding or keccak.
        uint padding;
        assembly ("memory-safe") {
            let remainder := and(mload(output), 31)
            if remainder { padding := shr(mul(remainder, 8), mload(add(add(output, 32), mload(output)))) }
        }
        require(padding == 0, "output padding");
        require(keccak256(sentinel) == digest, "sentinel");
        PreviousLogs.memCopyWrap(1, Keys.State, output);
        for (uint i; i < output.length; i += 72) {
            bytes32 asset;
            uint amount;
            assembly ("memory-safe") {
                asset := mload(add(add(output, 40), i))
                amount := mload(add(add(output, 72), i))
            }
            balances[account][asset] += amount;
        }
        if (credit != 0) {
            balances[account][chainAsset] += credit;
            logBalance(credit);
        }
        used = start - gasleft();
    }

    /// @dev Exercise arbitrary logical cursors and errors without the roundtrip.
    function probe(bytes calldata input, bytes memory state, uint position, uint end, uint value)
        external returns (bytes memory output, uint credit)
    {
        uint start;
        assembly ("memory-safe") { start := input.offset }
        return bootstrap(state, (start + position) | ((start + end) << 32), value);
    }
}

contract BootstrapShortCurrent is ExecuteBootstrap, BootstrapShortHarness {
    constructor() Runtime(0) {}
    function bootstrap(bytes memory state, uint cur, uint value) internal override returns (bytes memory output, uint credit) {
        (, output, credit) = executeBootstrap(bytes32(uint(uint160(msg.sender))), state, cur, value);
    }
    function logPipeline(uint value) internal override { PreviousLogs.pipeline(bytes32(uint(uint160(msg.sender))), value, Entities.Account); }
    function logBalance(uint value) internal override { LogsBalance151.balance(chainAsset, value, (Entities.Account | (Actions.Cashin << 32))); }
}

contract BootstrapShortStock is BootstrapStock150, BootstrapShortHarness {
    constructor() Runtime(0) {}
    function bootstrap(bytes memory state, uint cur, uint value) internal override returns (bytes memory output, uint credit) {
        (, output, credit) = executeBootstrap(bytes32(uint(uint160(msg.sender))), state, cur, value);
    }
    function logPipeline(uint value) internal override { LogsStock150.pipeline(bytes32(uint(uint160(msg.sender))), value, Entities.Account); }
    function logBalance(uint value) internal override { LogsStock150.balance(chainAsset, value, (Entities.Account | (Actions.Cashin << 32))); }
}

contract BootstrapShortZero is BootstrapZero150, BootstrapShortHarness {
    constructor() Runtime(0) {}
    function bootstrap(bytes memory state, uint cur, uint value) internal override returns (bytes memory output, uint credit) {
        (, output, credit) = executeBootstrap(bytes32(uint(uint160(msg.sender))), state, cur, value);
    }
    function logPipeline(uint value) internal override { PreviousLogs.pipeline(bytes32(uint(uint160(msg.sender))), value, Entities.Account); }
    function logBalance(uint value) internal override { LogsBalance151.balance(chainAsset, value, (Entities.Account | (Actions.Cashin << 32))); }
}

contract BootstrapShortLogged151 is BootstrapLogged151, BootstrapShortHarness {
    constructor() Runtime(0) {}
    function bootstrap(bytes memory state, uint cur, uint value) internal override returns (bytes memory output, uint credit) {
        (, output, credit) = executeBootstrap(bytes32(uint(uint160(msg.sender))), state, cur, value);
    }
    function logPipeline(uint value) internal override { PreviousLogs.pipeline(bytes32(uint(uint160(msg.sender))), value, Entities.Account); }
    function logBalance(uint value) internal override { LogsBalance151.balance(chainAsset, value, (Entities.Account | (Actions.Cashin << 32))); }
}
