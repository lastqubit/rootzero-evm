// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

/// @title Variants
/// @notice Standard lane variant keys that refine what the blocks on a lane carry.
/// Each key is `bytes4(keccak256("<block>.<name>"))`, where `<block>` is the block
/// name without its leading `#`. `Specs.toVariant` packs a variant into spec bits
/// 63-32; the blocks keep their wire key.
/// @dev Variants are declarations for offchain tools only. Nothing onchain reads
/// or enforces them. On an output lane a variant is a promise about the emitted
/// blocks; on a state lane it is a requirement on the incoming blocks. "Incoming"
/// below means unchanged from the state block at the same position.
library Variants {
    // POSITION variants

    /// @dev POSITION with a debt leg only: `asset` and `amount` zero, `liability` and `debt` nonzero.
    bytes4 constant Debt = bytes4(keccak256("position.debt"));
    /// @dev POSITION whose counterparty is a nonzero account.
    bytes4 constant Counterparty = bytes4(keccak256("position.counterparty"));
    /// @dev POSITION with a zero counterparty, booked on the account's own ledger.
    bytes4 constant Ledger = bytes4(keccak256("position.ledger"));
    /// @dev POSITION with every field incoming.
    bytes4 constant Same = bytes4(keccak256("position.same"));
    /// @dev POSITION with incoming `asset` and `liability`, any quantities, and a zero counterparty.
    bytes4 constant Realized = bytes4(keccak256("position.realized"));
    /// @dev POSITION with a zero `debt`; every other field incoming.
    bytes4 constant Repaid = bytes4(keccak256("position.repaid"));
    /// @dev POSITION with any `asset` and `amount`; debt leg and counterparty incoming.
    bytes4 constant KeepDebt = bytes4(keccak256("position.keepDebt"));
    /// @dev POSITION with any `liability` and `debt`; asset leg and counterparty incoming.
    bytes4 constant KeepAsset = bytes4(keccak256("position.keepAsset"));
}
