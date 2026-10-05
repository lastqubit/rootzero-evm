// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

import {CommandBase, Execution, Executions, Specs} from "./Base.sol";
import {Blocks} from "../codec/Blocks.sol";
import {Counterparty} from "../core/Counterparty.sol";
import {Actions} from "../utils/Actions.sol";
import {Cursors} from "../utils/Cursors.sol";

using Executions for Execution;

/// @notice Hook implemented by hosts that swap an exact input amount.
abstract contract SwapExactInHook {
    /// @notice Swap an exact liability quantity for an output asset in one hop.
    /// @dev The implementation validates amounts and asset pairs and defines
    /// supported pools, fees, and settlement of intermediate assets.
    /// @param liability Input asset to pay.
    /// @param debt Exact quantity of liability to pay.
    /// @param asset Output asset to receive.
    /// @return amount Net quantity of asset received.
    function swapExactIn(
        bytes32 liability,
        uint debt,
        bytes32 asset
    ) internal virtual returns (uint amount);
}

/// @notice Hook implemented by hosts that swap for an exact output amount.
abstract contract SwapExactOutHook {
    /// @notice Obtain an exact asset quantity using an input liability in one hop.
    /// @dev The implementation validates amounts and asset pairs and defines
    /// supported pools, fees, and settlement of intermediate assets.
    /// @param asset Desired output asset.
    /// @param amount Exact quantity of asset to receive.
    /// @param liability Input asset to pay.
    /// @return debt Total quantity of liability required.
    function swapExactOut(
        bytes32 asset,
        uint amount,
        bytes32 liability
    ) internal virtual returns (uint debt);
}

/// @notice Swap each SWAP input's exact input amount and return one POSITION per item.
abstract contract SwapExactIn is CommandBase, SwapExactInHook, Counterparty {
    uint private constant OUTPUT = Specs.Position | Actions.Swap;

    uint private immutable descriptor;
    uint private immutable id;

    constructor() {
        (id, descriptor) = command("swapExactIn", Specs.Empty, Specs.Swap, OUTPUT, 0);
    }

    /// @notice Process a SWAP batch with empty state; empty input is a valid empty batch.
    /// @dev Validates ASSET hops and calls the hook once per hop. An empty LIST
    /// calls no hook and returns equal asset/liability and amount/debt.
    /// Produces one aggregate position using the immutable settlement counterparty;
    /// intermediate assets must be settled internally by the hook implementation.
    /// The runner logs the batch in an endpoint-prefixed OUTPUT with Actions.Swap.
    /// Subsequent position-constraint commands enforce limits.
    /// @return Aggregate POSITION blocks, one per SWAP in input order.
    /// @return Zero native budget credit.
    function swapExactIn(bytes calldata context) external onlyCommand returns (bytes memory, uint) {
        return runCommand(id, descriptor, context, swapExactInOne);
    }

    function swapExactInOne(Execution memory exec) private {
        (bytes32 liability, uint debt, uint hopsCur) = exec.unpackSwap();
        bytes32 asset = liability;
        uint amount = debt;

        while (Cursors.more(hopsCur)) {
            bytes32 next;
            (next, hopsCur) = Blocks.unpackAsset(hopsCur);
            amount = swapExactIn(asset, amount, next);
            asset = next;
        }

        exec.outputPosition(asset, amount, liability, debt, counterparty);
    }
}

/// @notice Swap for each SWAP input's exact output amount and return one POSITION per item.
abstract contract SwapExactOut is CommandBase, SwapExactOutHook, Counterparty {
    uint private constant OUTPUT = Specs.Position | Actions.Swap;

    uint private immutable descriptor;
    uint private immutable id;

    constructor() {
        (id, descriptor) = command("swapExactOut", Specs.Empty, Specs.Swap, OUTPUT, 0);
    }

    /// @notice Process a SWAP batch with empty state; hops run from output toward input.
    /// @dev Validates ASSET hops and calls the hook once per hop. An empty LIST
    /// calls no hook and returns equal asset/liability and amount/debt.
    /// Produces one aggregate position using the immutable settlement counterparty;
    /// intermediate assets must be settled internally by the hook implementation.
    /// The runner logs the batch in an endpoint-prefixed OUTPUT with Actions.Swap.
    /// Subsequent position-constraint commands enforce limits.
    /// @return Aggregate POSITION blocks, one per SWAP in input order.
    /// @return Zero native budget credit.
    function swapExactOut(bytes calldata context) external onlyCommand returns (bytes memory, uint) {
        return runCommand(id, descriptor, context, swapExactOutOne);
    }

    function swapExactOutOne(Execution memory exec) private {
        (bytes32 asset, uint amount, uint hopsCur) = exec.unpackSwap();
        bytes32 liability = asset;
        uint debt = amount;

        while (Cursors.more(hopsCur)) {
            bytes32 next;
            (next, hopsCur) = Blocks.unpackAsset(hopsCur);
            debt = swapExactOut(liability, debt, next);
            liability = next;
        }

        exec.outputPosition(asset, amount, liability, debt, counterparty);
    }
}
