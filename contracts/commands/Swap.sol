// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;
import {Logs} from "../codec/Logs.sol";

import {CommandBase, Execution, Executions, Specs} from "./Base.sol";
import {Blocks} from "../codec/Blocks.sol";
import {Counterparty} from "../core/Counterparty.sol";
import {Position} from "../core/Types.sol";
import {Cursors} from "../utils/Cursors.sol";
import {UnexpectedValue} from "../utils/Errors.sol";

using Executions for Execution;

/// @title SwapExactInputHook
/// @notice Hook implemented by hosts that swap an exact input amount.
abstract contract SwapExactInputHook {
    /// @notice Swap an exact liability quantity for an output asset in one hop.
    /// @dev The implementation validates amounts and asset pairs and defines
    /// supported pools, fees, and settlement of intermediate assets.
    /// @param liability Input asset to pay.
    /// @param debt Exact quantity of liability to pay.
    /// @param asset Output asset to receive.
    /// @return amount Net quantity of asset received.
    function swapExactInput(
        bytes32 liability,
        uint debt,
        bytes32 asset
    ) internal virtual returns (uint amount);
}

/// @title SwapExactOutputHook
/// @notice Hook implemented by hosts that swap for an exact output amount.
abstract contract SwapExactOutputHook {
    /// @notice Obtain an exact asset quantity using an input liability in one hop.
    /// @dev The implementation validates amounts and asset pairs and defines
    /// supported pools, fees, and settlement of intermediate assets.
    /// @param asset Desired output asset.
    /// @param amount Exact quantity of asset to receive.
    /// @param liability Input asset to pay.
    /// @return debt Total quantity of liability required.
    function swapExactOutput(
        bytes32 asset,
        uint amount,
        bytes32 liability
    ) internal virtual returns (uint debt);
}

/// @title SwapExactInput
/// @notice Swap each SWAP input's exact input amount and return one POSITION per item.
abstract contract SwapExactInput is CommandBase, SwapExactInputHook, Counterparty {
    uint private immutable descriptor;

    constructor() {
        (, descriptor) = command("swapExactInput", Specs.Empty, Specs.Swap, Specs.Position, Logs.Output);
    }

    /// @notice Process a SWAP batch with empty state; empty input is a valid empty batch.
    /// @dev Validates ASSET hops and calls the hook once per hop. An empty LIST
    /// calls no hook and returns equal asset/liability and amount/debt.
    /// Produces one aggregate position using the immutable settlement counterparty;
    /// intermediate assets must be settled internally by the hook implementation.
    /// The runner logs the batch in an endpoint-prefixed OUTPUT with output logging enabled.
    /// Subsequent position-constraint commands enforce limits.
    /// @param context Exactly one CONTEXT block containing the account, state, and input streams.
    /// @return Aggregate POSITION blocks, one per SWAP in input order.
    /// @return Zero native budget credit.
    function swapExactInput(bytes calldata context) external onlyCommand returns (bytes memory, uint) {
        return runCommand(descriptor, context, swapExactInputOne);
    }

    /// @dev Decode one exact-input swap, traverse its hops, and append the aggregate position.
    /// @param exec Execution containing the account, source cursors, output writer, and native-value budget.
    function swapExactInputOne(Execution memory exec) private {
        (bytes32 liability, uint debt, uint hopsCur) = exec.unpackSwap();
        bytes32 asset = liability;
        uint amount = debt;

        while (Cursors.more(hopsCur)) {
            bytes32 next;
            (next, hopsCur) = Blocks.unpackAsset(hopsCur);
            amount = swapExactInput(asset, amount, next);
            asset = next;
        }

        exec.outputPosition(asset, amount, liability, debt, counterparty);
    }
}

/// @title SwapExactOutput
/// @notice Swap for each SWAP input's exact output amount and return one POSITION per item.
abstract contract SwapExactOutput is CommandBase, SwapExactOutputHook, Counterparty {
    uint private immutable descriptor;

    constructor() {
        (, descriptor) = command("swapExactOutput", Specs.Empty, Specs.Swap, Specs.Position, Logs.Output);
    }

    /// @notice Process a SWAP batch with empty state; hops run from output toward input.
    /// @dev Validates ASSET hops and calls the hook once per hop. An empty LIST
    /// calls no hook and returns equal asset/liability and amount/debt.
    /// Produces one aggregate position using the immutable settlement counterparty;
    /// intermediate assets must be settled internally by the hook implementation.
    /// The runner logs the batch in an endpoint-prefixed OUTPUT with output logging enabled.
    /// Subsequent position-constraint commands enforce limits.
    /// @param context Exactly one CONTEXT block containing the account, state, and input streams.
    /// @return Aggregate POSITION blocks, one per SWAP in input order.
    /// @return Zero native budget credit.
    function swapExactOutput(bytes calldata context) external onlyCommand returns (bytes memory, uint) {
        return runCommand(descriptor, context, swapExactOutputOne);
    }

    /// @dev Decode one exact-output swap, traverse its reverse route, and append the aggregate position.
    /// @param exec Execution containing the account, source cursors, output writer, and native-value budget.
    function swapExactOutputOne(Execution memory exec) private {
        (bytes32 asset, uint amount, uint hopsCur) = exec.unpackSwap();
        bytes32 liability = asset;
        uint debt = amount;

        while (Cursors.more(hopsCur)) {
            bytes32 next;
            (next, hopsCur) = Blocks.unpackAsset(hopsCur);
            debt = swapExactOutput(liability, debt, next);
            liability = next;
        }

        exec.outputPosition(asset, amount, liability, debt, counterparty);
    }
}

/// @title SwapAssetExactInput
/// @notice Swap each POSITION's exact asset amount while preserving its debt side.
abstract contract SwapAssetExactInput is CommandBase, SwapExactInputHook, Counterparty {
    uint private immutable descriptor;

    constructor() {
        (, descriptor) = command("swapAssetExactInput", Specs.Position, Specs.List, Specs.Position, Logs.Output);
    }

    /// @notice Transform POSITION state using exactly one LIST of ASSET hops per position.
    /// @dev Routes exclude position.asset and run forward in list order. Each hop calls
    /// swapExactInput(current asset, exact amount, next asset) and propagates its output.
    /// Requires the incoming counterparty to equal the configured Counterparty,
    /// including for empty routes, or reverts UnexpectedValue. Empty routes call no hook.
    /// Hooks define pricing, amount validation, and settlement policy.
    /// Empty state with empty input is valid after caller access checks.
    /// @param context POSITION state paired with LIST input in the same order.
    /// @return One POSITION per input position, with only asset and amount updated;
    /// liability, debt, and counterparty are preserved. The runner logs OUTPUT.
    /// @return Zero native budget credit.
    function swapAssetExactInput(bytes calldata context) external onlyCommand returns (bytes memory, uint) {
        return runCommand(descriptor, context, swapAssetExactInputOne);
    }

    /// @dev Decode a position and its route, swap its asset side, and append the updated position.
    /// @param exec Execution containing the account, source cursors, output writer, and native-value budget.
    function swapAssetExactInputOne(Execution memory exec) private {
        Position memory position = exec.unpackPositionValue();
        if (position.counterparty != counterparty) revert UnexpectedValue();
        uint hopsCur = exec.unpackList();

        while (Cursors.more(hopsCur)) {
            bytes32 next;
            (next, hopsCur) = Blocks.unpackAsset(hopsCur);
            position.amount = swapExactInput(position.asset, position.amount, next);
            position.asset = next;
        }

        exec.outputPosition(position);
    }
}

/// @title SwapDebtExactOutput
/// @notice Replace each POSITION's debt side while obtaining its exact existing debt.
abstract contract SwapDebtExactOutput is CommandBase, SwapExactOutputHook, Counterparty {
    uint private immutable descriptor;

    constructor() {
        (, descriptor) = command("swapDebtExactOutput", Specs.Position, Specs.List, Specs.Position, Logs.Output);
    }

    /// @notice Transform POSITION state using exactly one LIST of ASSET hops per position.
    /// @dev Routes exclude position.liability and walk backward along the payment path,
    /// in list order: to replace a debt in C with payment in A through B, supply [B, A].
    /// Each hop calls swapExactOutput(current liability, exact debt, next payment asset)
    /// and propagates the required debt. Requires the incoming counterparty to equal
    /// the configured Counterparty, including for empty routes, or reverts UnexpectedValue.
    /// Empty routes call no hook. Hooks define pricing, amount validation, and settlement policy.
    /// Empty state with empty input is valid after caller access checks.
    /// @param context POSITION state paired with LIST input in the same order.
    /// @return One POSITION per input position, with only liability and debt updated;
    /// asset, amount, and counterparty are preserved. The runner logs OUTPUT.
    /// @return Zero native budget credit.
    function swapDebtExactOutput(bytes calldata context) external onlyCommand returns (bytes memory, uint) {
        return runCommand(descriptor, context, swapDebtExactOutputOne);
    }

    /// @dev Decode a position and its route, swap its debt side, and append the updated position.
    /// @param exec Execution containing the account, source cursors, output writer, and native-value budget.
    function swapDebtExactOutputOne(Execution memory exec) private {
        Position memory position = exec.unpackPositionValue();
        if (position.counterparty != counterparty) revert UnexpectedValue();
        uint hopsCur = exec.unpackList();

        while (Cursors.more(hopsCur)) {
            bytes32 next;
            (next, hopsCur) = Blocks.unpackAsset(hopsCur);
            position.debt = swapExactOutput(position.liability, position.debt, next);
            position.liability = next;
        }

        exec.outputPosition(position);
    }
}
