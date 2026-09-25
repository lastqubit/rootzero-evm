// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

/// @dev Right-aligned Blocks.InvalidBlock() selector for direct assembly use.
uint constant INVALID_BLOCK = 0xbe5a36cf;

/// @dev Right-aligned OutOfBounds() selector for direct assembly use.
uint constant OUT_OF_BOUNDS = 0xb4120f14;

/// @dev Right-aligned UnexpectedValue() selector for direct assembly use.
uint constant UNEXPECTED_VALUE = 0x123146a6;

/// @dev Right-aligned OutOfRange() selector for direct assembly use.
uint constant OUT_OF_RANGE = 0x7db3aba7;

/// @dev Thrown when an ID does not match the expected convention or type.
error InvalidId();

/// @dev Thrown when an opaque ID preimage is missing or unsupported.
error InvalidPreimage();

/// @dev Thrown when an identifier contains a zero address.
error ZeroAddress();

/// @dev Thrown when an address does not contain deployed bytecode.
error InvalidContract();

/// @dev Thrown when a query fails.
error QueryFailed();

/// @dev Thrown when sending the chain asset fails.
error SendFailed();

/// @dev Thrown when an account ID does not match the expected family or type.
error InvalidAccount();

/// @dev Thrown when an asset ID does not match the expected type or chain.
error InvalidAsset();

/// @dev Thrown when an asset is not authorized for an operation.
error UnauthorizedAsset();

/// @dev Thrown when a required nonzero amount is zero.
error ZeroAmount();


/// @dev Thrown when a value falls outside its allowed range.
error OutOfRange();

/// @dev Thrown when an operation produces an amount other than the exact amount expected.
error UnexpectedAmount();

/// @dev Thrown when a value does not match the expected value.
error UnexpectedValue();

/// @dev Thrown when an operation attempts to spend more value than remains.
error InsufficientValue();

/// @dev Thrown when a value exceeds the target integer width.
error ValueOverflow();

/// @dev Thrown when a value is not evenly divisible by its divisor.
error NotDivisible();

/// @dev Thrown when an operation exceeds its logical data boundary.
error OutOfBounds();

/// @dev Thrown when a cursor is not at the expected absolute position.
error UnexpectedPosition();

/// @dev Thrown when a decoder or execution is finalized with unread data.
error UnconsumedData();

/// @dev Thrown when an operation requires empty state but receives state data.
error UnexpectedState();

/// @dev Thrown when an operation requires empty input but receives input data.
error UnexpectedInput();
