// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;
import {LegacyBlocks} from "./LegacyBlocks.sol";
import {LegacyMemory} from "./LegacyMemory.sol";
// Frozen execute adapters before Execute specialization.

import {Encoder} from "../codec/Encoder.sol";
import {Cursors} from "../utils/Cursors.sol";
import {Sizes, Specs, BALANCE_HEADER, BALANCE_CONSTRAINTS_HEADER, POSITION_HEADER, POSITION_CONSTRAINTS_HEADER} from "../codec/Specs.sol";
import {UnexpectedInput, UnexpectedState, InvalidAsset, INVALID_BLOCK, UNEXPECTED_VALUE, OUT_OF_RANGE} from "../utils/Errors.sol";
import {CommandBase} from "../commands/Base.sol";
import {DebitAccountHook} from "../core/Settlement.sol";
import {DebitAccount} from "../commands/Debit.sol";
import {CreditAccount} from "../commands/Credit.sol";
import {Cashout} from "../commands/Cashout.sol";
import {Settle} from "../commands/Settle.sol";
import {Authorize} from "../commands/admin/Authorize.sol";
import {CheckBalance} from "../commands/Balance.sol";
import {CheckPosition} from "../commands/Position.sol";

abstract contract PreviousExecuteBootstrap is CommandBase, DebitAccountHook {
    uint private immutable id;

    constructor() {
        (id,) = command("bootstrap", Specs.Empty, Specs.Bootstrap, Specs.Balance, 0);
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
        (uint abs, uint end) = Cursors.bounds(inputCur, Sizes.Bootstrap);
        // floor(input.length / 104) * 72 <= input.length, so multiplication cannot overflow.
        uint cur;
        unchecked {
            (output, cur) = Encoder.init((end - abs) / Sizes.Bootstrap * Sizes.Balance);
        }
        credit = value;

        while (abs < end) {
            (bytes32 asset, uint amount, uint budget) = LegacyBlocks.unpackBootstrap(abs);
            credit = bootstrap(account, asset, amount, budget, credit);
            (output, cur) = Encoder.writeBalance(cur, output, asset, amount);
            unchecked {
                abs += Sizes.Bootstrap;
            }
        }

        output = Encoder.finish(cur, output);
        return (true, output, credit);
    }
}

abstract contract PreviousExecuteDebitAccount is DebitAccount {
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
        (uint abs, uint end) = Cursors.bounds(inputCur, Sizes.AssetAmount);
        uint cur;
        (output, cur) = Encoder.init(end - abs);

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
}

abstract contract PreviousExecuteCreditAccount is CreditAccount {
    /// @notice Execute the inherited credit-account command from an internal pipeline.
    /// @param account Account credited by each balance.
    /// @param state BALANCE block stream held in pipeline memory.
    /// @param inputCur Cursor over empty input required by the command schema.
    /// @param value Native value assigned to the command; returned unused as credit.
    /// @return handled Always true because this helper executed the command.
    /// @return output Empty output state.
    /// @return credit Unused assigned native value.
    function executeCreditAccount(
        bytes32 account,
        bytes memory state,
        uint inputCur,
        uint value
    ) internal returns (bool handled, bytes memory output, uint credit) {
        if (uint32(inputCur) != uint32(inputCur >> 32)) revert UnexpectedInput();
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
}

abstract contract PreviousExecuteCashout is Cashout {
    /// @notice Execute cashout directly against chain-asset BALANCE state held in memory.
    /// @param account Account whose chain asset is withdrawn.
    /// @param state BALANCE block stream held in pipeline memory.
    /// @param inputCur Cursor over empty input required by the command schema.
    /// @param value Native value assigned to this command; returned unused as credit.
    /// @return handled Always true because this helper executed the command.
    /// @return output Empty output state.
    /// @return credit Unused assigned native value.
    function executeCashout(
        bytes32 account,
        bytes memory state,
        uint inputCur,
        uint value
    ) internal returns (bool handled, bytes memory output, uint credit) {
        if (uint32(inputCur) != uint32(inputCur >> 32)) revert UnexpectedInput();
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
}

abstract contract PreviousExecuteSettle is Settle {
    /// @notice Execute the inherited settle command from an internal pipeline.
    /// @dev The hook validates the counterparty and authorizes the exchange.
    /// @param account Account for which each position is settled.
    /// @param state POSITION block stream held in pipeline memory.
    /// @param inputCur Cursor over empty command input.
    /// @param value Native value assigned to the command; returned unused as credit.
    /// @return handled Always true because this helper executed the command.
    /// @return output Empty output state.
    /// @return credit Unused assigned native value.
    function executeSettle(
        bytes32 account,
        bytes memory state,
        uint inputCur,
        uint value
    ) internal returns (bool handled, bytes memory output, uint credit) {
        if (uint32(inputCur) != uint32(inputCur >> 32)) revert UnexpectedInput();
        (uint abs, uint end) = LegacyMemory.bounds(state, Sizes.Position);

        while (abs < end) {
            settle(account, LegacyMemory.unpackPositionValue(abs));
            unchecked {
                abs += Sizes.Position;
            }
        }

        return (true, "", value);
    }
}

abstract contract PreviousExecuteAuthorize is Authorize {
    /// @notice Authorize each NODE input block from an internal pipeline.
    /// @param account Authenticated pipeline account, required to be the admin.
    /// @param state Empty command state.
    /// @param inputCur Cursor over NODE block stream.
    /// @param value Assigned native value, returned unused as credit.
    /// @return handled Always true after successful execution.
    /// @return output Empty output state.
    /// @return credit Unused assigned native value.
    function executeAuthorize(
        bytes32 account,
        bytes memory state,
        uint inputCur,
        uint value
    ) internal returns (bool handled, bytes memory output, uint credit) {
        enforceAdmin(account, address(this));
        if (state.length != 0) revert UnexpectedState();

        (uint abs, uint end) = Cursors.bounds(inputCur, Sizes.B32);
        while (abs < end) {
            authorizeNode(LegacyBlocks.unpackNode(abs));
            unchecked {
                abs += Sizes.B32;
            }
        }

        return (true, "", value);
    }
}

abstract contract PreviousExecuteCheckBalance is CheckBalance {
    /// @notice Validate balances in place without unpacking or copying their blocks.
    /// @param state BALANCE block stream in memory.
    /// @param inputCur Cursor over exactly one calldata BALANCE_CONSTRAINTS block per balance.
    /// @param value Assigned native budget, returned unused.
    /// @return handled Always true.
    /// @return output The original state buffer, unchanged.
    /// @return credit Unused assigned native budget.
    function executeCheckBalance(
        bytes32,
        bytes memory state,
        uint inputCur,
        uint value
    ) internal pure returns (bool handled, bytes memory output, uint credit) {
        assembly ("memory-safe") {
            function fail(selector) {
                mstore(0, selector)
                revert(28, 4)
            }
            let inputSize := sub(and(shr(32, inputCur), 0xffffffff), and(inputCur, 0xffffffff))
            let size := mload(state)
            // floor(inputSize / 104) * 72 <= inputSize, so multiplication cannot overflow.
            if or(mod(inputSize, 104), iszero(eq(size, mul(div(inputSize, 104), 72)))) {
                fail(INVALID_BLOCK)
            }
            let start := add(state, 32)
            let end := add(start, size)
            let q := and(inputCur, 0xffffffff)
            // Strides include each block's eight-byte header.
            for {
                let p := start
            } lt(p, end) {
                p := add(p, 72)
                q := add(q, 104)
            } {
                if or(
                    iszero(eq(shr(192, mload(p)), BALANCE_HEADER)),
                    iszero(eq(shr(192, calldataload(q)), BALANCE_CONSTRAINTS_HEADER))
                ) {
                    fail(INVALID_BLOCK)
                }
                if iszero(eq(mload(add(p, 0x08)), calldataload(add(q, 0x08)))) {
                    fail(UNEXPECTED_VALUE)
                }
                let amount := mload(add(p, 0x28))
                if or(lt(amount, calldataload(add(q, 0x28))), gt(amount, calldataload(add(q, 0x48)))) {
                    fail(OUT_OF_RANGE)
                }
            }
        }

        return (true, state, value);
    }
}

abstract contract PreviousExecuteCheckPosition is CheckPosition {
    /// @notice Validate positions in place without unpacking or copying their blocks.
    /// @param state POSITION block stream in memory.
    /// @param inputCur Cursor over exactly one calldata POSITION_CONSTRAINTS block per position.
    /// @param value Assigned native budget, returned unused.
    /// @return handled Always true.
    /// @return output The original state buffer, unchanged.
    /// @return credit Unused assigned native budget.
    function executeCheckPosition(
        bytes32,
        bytes memory state,
        uint inputCur,
        uint value
    ) internal pure returns (bool handled, bytes memory output, uint credit) {
        assembly ("memory-safe") {
            function fail(selector) {
                mstore(0, selector)
                revert(28, 4)
            }
            let inputSize := sub(and(shr(32, inputCur), 0xffffffff), and(inputCur, 0xffffffff))
            let size := mload(state)
            if mod(size, 168) {
                fail(INVALID_BLOCK)
            }
            // floor(size / 168) * 136 <= size, so multiplication cannot overflow.
            if iszero(eq(inputSize, mul(div(size, 168), 136))) {
                fail(INVALID_BLOCK)
            }
            let start := add(state, 32)
            let end := add(start, size)
            let q := and(inputCur, 0xffffffff)
            // Strides include each block's eight-byte header.
            for {
                let p := start
            } lt(p, end) {
                p := add(p, 168)
                q := add(q, 136)
            } {
                if or(
                    iszero(eq(shr(192, mload(p)), POSITION_HEADER)),
                    iszero(eq(shr(192, calldataload(q)), POSITION_CONSTRAINTS_HEADER))
                ) {
                    fail(INVALID_BLOCK)
                }
                if or(
                    xor(mload(add(p, 0x08)), calldataload(add(q, 0x08))),
                    xor(mload(add(p, 0x48)), calldataload(add(q, 0x48)))
                ) {
                    fail(UNEXPECTED_VALUE)
                }
                if or(
                    lt(mload(add(p, 0x28)), calldataload(add(q, 0x28))),
                    gt(mload(add(p, 0x68)), calldataload(add(q, 0x68)))
                ) {
                    fail(OUT_OF_RANGE)
                }
            }
        }

        return (true, state, value);
    }
}
