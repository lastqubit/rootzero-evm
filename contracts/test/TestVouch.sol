// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

import {Cursors} from "../utils/Cursors.sol";
import {Blocks} from "../codec/Blocks.sol";
import {Keys} from "../codec/Keys.sol";
import {ExecuteSettle} from "../commands/Settle.sol";
import {ExecuteVouch} from "../commands/Vouch.sol";
import {Settlement, SettleHook} from "../core/Settlement.sol";
import {Balances} from "../core/Balances.sol";
import {Pipeline} from "../core/Pipeline.sol";
import {Runtime} from "../core/Runtime.sol";
import {TrustSlots} from "../core/Trust.sol";
import {Position} from "../core/Types.sol";
import {AccessDenied} from "../core/Access.sol";
import {InvalidBlock} from "../utils/Errors.sol";
import {Accounts} from "../utils/Accounts.sol";
import {Nodes} from "../utils/Nodes.sol";

/// @dev Commander that starts pipelines with VOUCH, runs external steps and settles locally.
contract TestVouchCommander is ExecuteVouch, ExecuteSettle, Settlement, Balances, Pipeline {
    address private immutable tester = msg.sender;
    mapping(uint => bool) private commands;
    uint public lastRemaining;

    constructor() Runtime(0, address(0)) {}

    function vouchCommandId() external view returns (uint) { return vouchId(); }
    function settleCommandId() external view returns (uint) { return settleId(); }
    function nativeAsset() external view returns (bytes32) { return chainAsset; }
    function setCommand(uint cmd, bool enabled) external { commands[cmd] = enabled; }
    function setTrusted(bytes32 id, bool trusted) external { TrustSlots.set(uint(id), trusted); }
    function seed(bytes32 account, bytes32 asset, uint amount) external { creditTo(account, asset, amount); }
    function balanceOf(bytes32 account, bytes32 asset) external view returns (uint) { return balances[account][asset]; }

    function run(bytes32 account, bytes calldata steps) external payable {
        lastRemaining = pipe(account, "", Cursors.wrap(steps), msg.value);
    }

    function enforceCaller(address caller) internal view override returns (address) {
        if (caller != tester && caller != address(this)) revert AccessDenied();
        return caller;
    }

    function enforceCommand(uint cmd) internal view override returns (bytes4, address) {
        if (cmd != vouchId() && cmd != settleId() && !commands[cmd]) revert AccessDenied();
        return Nodes.decode(cmd);
    }

    function execute(uint cmd, bytes32 account, bytes memory state, uint inputCur, uint value)
        internal override returns (bool, bytes memory, uint)
    {
        if (cmd == vouchId()) return executeVouch(account, state, inputCur, value);
        if (cmd == settleId()) return executeSettle(account, state, inputCur, value);
        return (false, state, 0);
    }

    function settle(bytes32 account, Position memory position) internal override(Settlement, SettleHook) {
        Settlement.settle(account, position);
    }

    function debitAccount(bytes32 account, bytes32 asset, uint amount) internal override {
        debitFrom(account, asset, amount);
    }

    function creditAccount(bytes32 account, bytes32 asset, uint amount) internal override {
        creditTo(account, asset, amount);
    }
}

/// @dev External consumer of exactly two TRUST state blocks and one AMOUNT input. Returns a
/// POSITION (2 out per 1 in) that the commander settles against this host's account.
contract TestTrustConsumer is Runtime {
    constructor(uint commander) Runtime(commander, address(0)) {}

    function consumeId() external view returns (uint) { return Nodes.toCommand("consume", address(this)); }

    function consume(bytes calldata context) external view returns (bytes memory, uint) {
        if (msg.sender != commanderAddr) revert AccessDenied();
        (, uint stateCur, uint inputCur) = Blocks.unpackContextExact(Cursors.wrap(context));
        uint assetIn;
        uint assetOut;
        (assetIn, stateCur) = Blocks.unpackTrust(stateCur);
        (assetOut, stateCur) = Blocks.unpackTrust(stateCur);
        if (!Cursors.done(stateCur)) revert InvalidBlock();
        (uint amountIn, uint rest) = Blocks.unpackAmount(inputCur);
        if (!Cursors.done(rest)) revert InvalidBlock();
        bytes memory out = abi.encodePacked(Keys.Position, uint32(160), assetOut, amountIn * 2, assetIn, amountIn, Accounts.toHost(host));
        return (out, 0);
    }
}
