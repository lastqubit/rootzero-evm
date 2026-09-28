// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;
import {CheckBalance} from "../commands/Balance.sol";
import {Withdraw} from "../commands/Withdraw.sol";
import {CommandBase} from "../commands/Base.sol";
import {Runtime} from "../core/Runtime.sol";
import {PreviousCommandCheckBalance, PreviousCommandWithdraw} from "./PreviousCommandBalance.sol";

/// @dev Identical host hook for both command variants. Records delivered balances;
/// token transfers are host-specific and deliberately outside this comparison.
abstract contract CommandBalanceHost is Runtime, CommandBase {
    mapping(bytes32 => mapping(bytes32 => uint)) public delivered;
    constructor() Runtime(0) {}
    function enforceCaller(address caller) internal pure override returns (address) { return caller; }
    /// @dev Measures the real external command, excluding transaction-level calldata gas.
    /// ABI encoding precedes the timer; CALL and returned-byte copying are included.
    function measure(bytes calldata context, bool withHook) external returns (uint used, bytes memory output, uint credit) {
        bytes4 selector = withHook ? bytes4(keccak256("withdraw(bytes)")) : bytes4(keccak256("checkBalance(bytes)"));
        bytes memory data = abi.encodeWithSelector(selector, context);
        uint initial = gasleft();
        (bool ok, bytes memory result) = address(this).call(data);
        used = initial - gasleft();
        if (!ok) assembly ("memory-safe") { revert(add(result, 32), mload(result)) }
        (output, credit) = abi.decode(result, (bytes, uint));
    }
    function record(bytes32 account, bytes32 asset, uint amount) internal {
        delivered[account][asset] += amount;
    }
}
contract CommandBalancePrevious is CommandBalanceHost, PreviousCommandCheckBalance, PreviousCommandWithdraw {
    function withdraw(bytes32 account, bytes32 asset, uint amount) internal override { record(account, asset, amount); }
}
contract CommandBalanceCurrent is CommandBalanceHost, CheckBalance, Withdraw {
    function withdraw(bytes32 account, bytes32 asset, uint amount) internal override { record(account, asset, amount); }
}
