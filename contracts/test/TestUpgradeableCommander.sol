// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

import {Ownable, Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {Ownable2StepUpgradeable} from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import {ReentrancyGuardTransient} from "@openzeppelin/contracts/utils/ReentrancyGuardTransient.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Host, Pipeline, Balances, Settlement, sendChainAsset} from "../Core.sol";
import {Cursors, Logs} from "../Codec.sol";
import {Accounts, Nodes} from "../Utils.sol";
import {
    PipePayablePort, DebitAccountPort, CreditAccountPort, BookPort,
    ExecuteBootstrap, ExecuteCreditAccount, ExecuteSettle, ExecuteCheckPosition,
    ExecuteCheckBalance, ExecuteCashout, ExecuteAuthorize, ExecuteDebitAccount, GetBalance
} from "../Endpoints.sol";

/// @dev Mirrors commander Main/Base using the current protocol API. Shared by both
/// deployments so ledger, logging, entry limits, reentrancy and dispatch work match.
abstract contract CommanderTestCore is
    Host, Pipeline, Balances, Settlement, PipePayablePort, DebitAccountPort,
    CreditAccountPort, BookPort, ExecuteBootstrap, ExecuteCreditAccount, ExecuteSettle,
    ExecuteCheckPosition, ExecuteCheckBalance, ExecuteCashout, ExecuteAuthorize,
    GetBalance, ReentrancyGuardTransient
{
    uint public immutable chain = Nodes.localChain();
    error InvalidSteps();

    constructor(address self) Host(0, "commander", self) {}

    function getBalance(bytes32 account, bytes32 asset) internal view override returns (uint) {
        return balances[account][asset];
    }

    function debitAccount(bytes32 account, bytes32 asset, uint amount) internal override {
        if (amount == 0) return;
        Logs.balance(account, asset, debitFrom(account, asset, amount));
    }

    function creditAccount(bytes32 account, bytes32 asset, uint amount) internal override {
        if (amount == 0) return;
        Logs.balance(account, asset, creditTo(account, asset, amount));
    }

    function cashout(bytes32 account, uint amount) internal override {
        if (amount != 0) sendChainAsset(account, amount);
    }

    function cashin(bytes32 account, uint value) internal override {
        if (value != 0) creditAccount(account, chainAsset, value);
    }

    function execute(uint cmd, bytes32 account, bytes memory state, uint input, uint value)
        internal virtual override returns (bool, bytes memory, uint)
    {
        if (cmd == bootstrapId()) return executeBootstrap(account, state, input, value);
        if (cmd == creditAccountId()) return executeCreditAccount(account, state, input, value);
        if (cmd == settleId()) return executeSettle(account, state, input, value);
        if (cmd == checkPositionId()) return executeCheckPosition(account, state, input, value);
        if (cmd == checkBalanceId()) return executeCheckBalance(account, state, input, value);
        if (cmd == cashoutId()) return executeCashout(account, state, input, value);
        if (cmd == authorizeId()) return executeAuthorize(account, state, input, value);
        return (false, "", 0);
    }

    function rootzero(bytes calldata steps, uint deadline) external payable nonReentrant onlyActive(deadline) {
        if (steps.length > 4096) revert InvalidSteps();
        bytes32 account = Accounts.toUser(msg.sender);
        cashin(account, pipe(account, "", Cursors.wrap(steps), msg.value));
    }

    // Inspection only; neither getter participates in timed pipeline execution.
    function nativeAsset() external view returns (bytes32) { return chainAsset; }
    function balanceOf(bytes32 account, bytes32 asset) external view returns (uint) { return balances[account][asset]; }
    function isAuthorized(uint node) external view returns (bool) { return nodes[node]; }
}

contract TestCommanderDirect is CommanderTestCore, Ownable2Step {
    constructor(address owner) CommanderTestCore(address(0)) Ownable(owner) {}

    function govern(bytes calldata steps, uint deadline) external payable onlyOwner onlyActive(deadline) {
        pipe(admin, "", Cursors.wrap(steps), msg.value);
    }
}

contract TestCommanderUpgradeable is CommanderTestCore, Ownable2StepUpgradeable, UUPSUpgradeable {
    error WrongExecutionAddress();

    constructor(address self) CommanderTestCore(self) { _disableInitializers(); }

    function initialize(address owner) external initializer {
        if (hostAddr() != address(this)) revert WrongExecutionAddress();
        __Ownable_init(owner);
        __Ownable2Step_init();
    }

    function govern(bytes calldata steps, uint deadline) external payable onlyOwner onlyActive(deadline) {
        pipe(admin, "", Cursors.wrap(steps), msg.value);
    }

    function _authorizeUpgrade(address implementation) internal view override onlyOwner {
        if (CommanderTestCore(payable(implementation)).host() != host) revert WrongExecutionAddress();
    }
}

/// @dev Adds an inherited command, a local execute branch, and append-only state.
contract TestCommanderUpgradeableV2 is TestCommanderUpgradeable, ExecuteDebitAccount {
    uint public upgradeMarker;

    constructor(address self) TestCommanderUpgradeable(self) {}

    function initializeV2() external reinitializer(2) onlyOwner { upgradeMarker = 42; }

    function execute(uint cmd, bytes32 account, bytes memory state, uint input, uint value)
        internal override returns (bool, bytes memory, uint)
    {
        if (cmd == debitAccountId()) return executeDebitAccount(account, state, input, value);
        return super.execute(cmd, account, state, input, value);
    }
}

contract TestCommanderERC1967Proxy is ERC1967Proxy {
    constructor(address implementation, bytes memory data) ERC1967Proxy(implementation, data) {}
}

interface ICommanderTestEntry {
    function rootzero(bytes calldata steps, uint deadline) external payable;
}

contract TestCommanderReentrantReceiver {
    address private target;
    bytes4 public reentryError;

    function withdraw(address commander, bytes calldata steps) external payable {
        target = commander;
        ICommanderTestEntry(commander).rootzero{value: msg.value}("", type(uint).max);
        ICommanderTestEntry(commander).rootzero(steps, type(uint).max);
    }

    receive() external payable {
        (bool success, bytes memory errorData) = target.call(
            abi.encodeCall(ICommanderTestEntry.rootzero, ("", type(uint).max))
        );
        require(!success && errorData.length >= 4);
        reentryError = bytes4(errorData);
    }
}
