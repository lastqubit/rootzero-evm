// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

import {Accounts} from "../utils/Accounts.sol";

import { Host } from "../core/Host.sol";
import { Allocate } from "../commands/Allocate.sol";
import { Bootstrap } from "../commands/Bootstrap.sol";
import { ExecuteCashout } from "../commands/Cashout.sol";
import { Deposit, DepositPayable } from "../commands/Deposit.sol";
import { Withdraw } from "../commands/Withdraw.sol";
import { ExecuteCreditAccount } from "../commands/Credit.sol";
import { ExecuteDebitAccount } from "../commands/Debit.sol";
import { Payout } from "../commands/Payout.sol";
import { Provision, ProvisionPayable } from "../commands/Provision.sol";
import { RelayPayable, RelayBalancePayable } from "../commands/Relay.sol";
import { RecoverPayable } from "../commands/Recover.sol";
import { Realize } from "../commands/Realize.sol";
import { ExecuteSettle, SettlePayable } from "../commands/Settle.sol";
import { Pipeline } from "../core/Pipeline.sol";
import { Settlement, SettleHook } from "../core/Settlement.sol";
import { BookPort } from "../ports/Book.sol";
import { AllowAssets } from "../commands/admin/AllowAssets.sol";
import { DenyAssets } from "../commands/admin/DenyAssets.sol";
import { Allowance } from "../commands/admin/Allowance.sol";
import { RevokeAllowance, RevokeAsset } from "../guards/Revoke.sol";
import { HostAmount, Limits, Position } from "../core/Types.sol";
import { Execution, Executions } from "../execution/Execution.sol";
import { Blocks } from "../codec/Blocks.sol";
import { Specs } from "../codec/Specs.sol";
import { AmountOutOfRange, UnexpectedValue } from "../utils/Errors.sol";

using Executions for Execution;

contract TestHost is
    Host,
    Allocate,
    Bootstrap,
    ExecuteCashout,
    Deposit,
    DepositPayable,
    Withdraw,
    ExecuteCreditAccount,
    ExecuteDebitAccount,
    Payout,
    Provision,
    ProvisionPayable,
    RelayPayable,
    RelayBalancePayable,
    RecoverPayable,
    Realize,
    ExecuteSettle,
    SettlePayable,
    Settlement,
    Pipeline,
    BookPort,
    AllowAssets,
    DenyAssets,
    Allowance,
    RevokeAllowance,
    RevokeAsset
{
    event AllocateCalled(uint host_, bytes32 account, bytes32 asset, uint amount);
    event CashoutCalled(bytes32 account, uint amount);
    event DepositCalled(bytes32 account, bytes32 asset, uint amount);
    event DepositPayableCalled(bytes32 account, bytes32 asset, uint amount, uint remaining);
    event WithdrawCalled(bytes32 account, bytes32 asset, uint amount);
    event CreditToCalled(bytes32 account, bytes32 asset, uint amount, uint returned);
    event DebitFromCalled(bytes32 account, bytes32 asset, uint amount, uint returned);
    event PayoutCalled(bytes32 account, bytes32 to, bytes32 asset, uint amount);
    event ProvisionCalled(uint host_, bytes32 account, bytes32 asset, uint amount);
    event ProvisionPayableCalled(uint host_, bytes32 account, bytes32 asset, uint amount, uint remaining);
    event RelayCalled(uint portal, uint resources, bytes32 account, bytes context);
    event RecoverCalled(uint handler, uint resources, bytes32 key, bytes witness, uint value);
    event RealizeCalled(bytes32 account, bytes32 asset, uint amount, bytes32 liability, uint debt, bytes32 counterparty);
    event SettleCalled(
        bytes32 account,
        bytes32 asset,
        uint amount,
        bytes32 liability,
        uint debt
    );
    event SettlePayableCalled(
        bytes32 account,
        bytes32 asset,
        uint amount,
        bytes32 liability,
        uint debt,
        uint remaining
    );
    event AllowAssetCalled(bytes32 asset);
    event DenyAssetCalled(bytes32 asset);
    event AllowanceCalled(uint host_, bytes32 asset, uint amount);
    event SettleCounterpartyChecked(bytes32 counterparty);
    bytes32 private acceptedSettleCounterparty;

    function setAcceptedSettleCounterparty(bytes32 counterparty) external {
        acceptedSettleCounterparty = counterparty;
    }

    function checkSettleCounterparty(bytes32 counterparty) private {
        if (counterparty != acceptedSettleCounterparty) revert UnexpectedValue();
        emit SettleCounterpartyChecked(counterparty);
    }

    uint public depositFee;
    uint public realizeFee;
    uint public realizeDebtFee;

    constructor(uint rootzero) Host(rootzero) Allocate() Deposit() Provision() {
        schema(3, 64, "uint portal, uint resources", bytes32("relay.input"));
    }

    function allocate(bytes32 account, HostAmount memory custody) internal override {
        emit AllocateCalled(custody.host, account, custody.asset, custody.amount);
    }

    function cashout(bytes32 account, uint amount) internal override {
        emit CashoutCalled(account, amount);
    }

    function setDepositFee(uint fee) external {
        depositFee = fee;
    }

    function setRealizeFee(uint fee) external {
        realizeFee = fee;
    }

    function setRealizeDebtFee(uint fee) external {
        realizeDebtFee = fee;
    }

    function deposit(bytes32 account, bytes32 asset, uint amount) internal override returns (uint) {
        emit DepositCalled(account, asset, amount);
        return amount - depositFee;
    }

    function deposit(
        bytes32 account,
        bytes32 asset,
        uint amount,
        Execution memory funds
    ) internal override returns (uint) {
        emit DepositPayableCalled(account, asset, funds.useValue(amount), funds.budget);
        return amount - depositFee;
    }

    function withdraw(bytes32 account, bytes32 asset, uint amount) internal override {
        emit WithdrawCalled(account, asset, amount);
    }

    event SettleLimitsCalled(uint amount, uint debt);

    function settle(bytes32 account, Position memory position, Limits memory limits) internal override(SettleHook) {
        checkSettleCounterparty(position.counterparty);
        if (position.amount < limits.amount || position.debt > limits.debt) revert AmountOutOfRange();
        emit SettleLimitsCalled(limits.amount, limits.debt);
        emit SettleCalled(account, position.asset, position.amount, position.liability, position.debt);
    }

    function settle(bytes32 account, Position memory position, Limits memory limits, Execution memory funds) internal override {
        checkSettleCounterparty(position.counterparty);
        if (position.amount < limits.amount || position.debt > limits.debt) revert AmountOutOfRange();
        emit SettleLimitsCalled(limits.amount, limits.debt);
        funds.useValue(position.amount + position.debt);
        emit SettlePayableCalled(account, position.asset, position.amount, position.liability, position.debt, funds.budget);
    }

    function creditAccount(bytes32 account, bytes32 asset, uint amount) internal override {
        emit CreditToCalled(account, asset, amount, amount);
    }

    function debitAccount(bytes32 account, bytes32 asset, uint amount) internal override {
        emit DebitFromCalled(account, asset, amount, amount);
    }

    function payout(bytes32 account, bytes32 to, bytes32 asset, uint amount) internal override {
        emit PayoutCalled(account, to, asset, amount);
    }

    function realize(bytes32 account, Position memory position) internal override returns (Position memory) {
        if (position.counterparty != Accounts.toHost(host)) revert UnexpectedValue();
        emit RealizeCalled(account, position.asset, position.amount, position.liability, position.debt, position.counterparty);
        position.amount -= realizeFee;
        position.debt -= realizeDebtFee;
        position.counterparty = bytes32(0);
        return position;
    }

    function provision(bytes32 account, HostAmount memory custody) internal override {
        emit ProvisionCalled(custody.host, account, custody.asset, custody.amount);
    }

    function provision(
        bytes32 account,
        HostAmount memory custody,
        Execution memory funds
    ) internal override {
        emit ProvisionPayableCalled(
            custody.host, account, custody.asset, funds.useValue(custody.amount), funds.budget
        );
    }

    function relay(
        bytes32 account,
        bytes calldata input,
        bytes memory context,
        Execution memory
    ) internal override {
        uint abs = Blocks.exact(input, Specs.create(3, 64));
        uint portal = uint(Blocks.read32(abs));
        uint resources = uint(Blocks.read32(abs + 32));
        emit RelayCalled(portal, resources, account, context);
    }

    function recover(
        uint handler,
        uint resources,
        bytes32 key,
        bytes calldata witness,
        Execution memory funds
    ) internal override {
        emit RecoverCalled(handler, resources, key, witness, funds.useResourceValue(resources));
    }

    function allowAsset(bytes32 asset) internal override {
        emit AllowAssetCalled(asset);
    }

    function denyAsset(bytes32 asset) internal override {
        emit DenyAssetCalled(asset);
    }

    function allowance(uint peer, bytes32 asset, uint amount) internal override {
        emit AllowanceCalled(peer, asset, amount);
    }

    function execute(
        uint cid,
        bytes32 account,
        bytes memory state,
        bytes calldata input,
        uint value
    ) internal override returns (bool handled, bytes memory nextState, uint credit) {
        if (cid == bootstrapId()) {
            enforceCommand(cid);
            return executeBootstrap(account, state, input, value);
        }
        if (cid == cashoutId()) {
            enforceCommand(cid);
            return executeCashout(account, state, input, value);
        }
        if (cid == debitAccountId()) {
            enforceCommand(cid);
            return executeDebitAccount(account, state, input, value);
        }
        if (cid == creditAccountId()) {
            enforceCommand(cid);
            return executeCreditAccount(account, state, input, value);
        }
        if (cid == settleId()) {
            enforceCommand(cid);
            return executeSettle(account, state, input, value);
        }
        return (false, state, 0);
    }

    function testPipe(bytes32 account, bytes memory state, bytes calldata steps) external payable {
        Execution memory exec = Executions.open();
        exec.account = account;
        uint budget = exec.drainBudget();
        exec.budget = pipe(account, state, steps, budget);
        uint credit;
        (, credit) = exec.close();
        book(bytes32(0), account, chainAsset, credit, bytes32(0), 0);
    }

    function getAdminAccount() external view returns (bytes32) {
        return admin;
    }

    function getCommander() external view returns (uint) {
        return commander;
    }

    function getCommanderAddr() external view returns (address) {
        return commanderAddr;
    }

    function isAuthorized(uint node) external view returns (bool) {
        return nodes[node];
    }

    function testEnforceNode(uint node) external view returns (bytes4, address) {
        return enforceNode(node);
    }

    function testEnforceCommand(uint cmd) external view returns (bytes4, address) {
        return enforceCommand(cmd);
    }

    function testEnforcePort(uint port) external view returns (bytes4, address) {
        return enforcePort(port);
    }

    function testAuthorizeId() external view returns (uint) {
        return authorizeId();
    }

    function testUnauthorizeId() external view returns (uint) {
        return unauthorizeId();
    }

    function setGuardianAccount(bytes32 account, bool active) external {
        setGuardian(account, active);
    }

    function isGuardianAddress(address addr) external view returns (bool) {
        return isGuardian(addr);
    }

}




