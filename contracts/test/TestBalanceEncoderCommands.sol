// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

import {CheckBalance} from "../commands/Balance.sol";
import {DebitAccount} from "../commands/Debit.sol";
import {CommandBase} from "../commands/Base.sol";
import {Runtime} from "../core/Runtime.sol";
import {PreviousEncoderCheckBalance, PreviousEncoderDebitAccount} from "./PreviousBalanceEncoderCommands.sol";

abstract contract BalanceEncoderCommandHost is Runtime, CommandBase {
    mapping(bytes32 => mapping(bytes32 => uint)) public debited;
    constructor() Runtime(0) {}
    function enforceCaller(address caller) internal pure override returns (address) { return caller; }
    function measure(bytes calldata context, bool debit) external returns (uint used, bytes memory output, uint credit) {
        bytes4 selector = debit ? bytes4(keccak256("debitAccount(bytes)")) : bytes4(keccak256("checkBalance(bytes)"));
        bytes memory data = abi.encodeWithSelector(selector, context);
        uint initial = gasleft();
        (bool ok, bytes memory result) = address(this).call(data);
        used = initial - gasleft();
        if (!ok) assembly ("memory-safe") { revert(add(result, 32), mload(result)) }
        (output, credit) = abi.decode(result, (bytes, uint));
    }
}

contract TestBalanceEncoderCommandsPrevious is BalanceEncoderCommandHost, PreviousEncoderCheckBalance, PreviousEncoderDebitAccount {
    function debitAccount(bytes32 account, bytes32 asset, uint amount) internal override { debited[account][asset] += amount; }
}

contract TestBalanceEncoderCommands is BalanceEncoderCommandHost, CheckBalance, DebitAccount {
    function debitAccount(bytes32 account, bytes32 asset, uint amount) internal override { debited[account][asset] += amount; }
}
