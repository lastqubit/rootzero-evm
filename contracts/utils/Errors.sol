// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

/// @dev Right-aligned InvalidBlock() selector for direct assembly use.
uint constant INVALID_BLOCK = 0xbe5a36cf;

/// @dev Right-aligned OutOfBounds() selector for direct assembly use.
uint constant OUT_OF_BOUNDS = 0xb4120f14;

/// @dev Right-aligned UnexpectedValue() selector for direct assembly use.
uint constant UNEXPECTED_VALUE = 0x123146a6;

/// @dev Right-aligned OutOfRange() selector for direct assembly use.
uint constant OUT_OF_RANGE = 0x7db3aba7;

/// @dev Right-aligned TooManySteps() selector for direct assembly use.
uint constant TOO_MANY_STEPS = 0x5cdc2c78;

/// @dev Right-aligned StepFailed(uint256,uint256,bytes) selector for direct assembly use.
uint constant STEP_FAILED = 0x7837be7d;

/// @dev A block key or payload size does not match its expected shape.
error InvalidBlock();

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

/// @dev Thrown when a pipeline exceeds the 64 steps its record index can address.
error TooManySteps();

/// @dev Thrown by a pipeline when an external step call fails. Host-local steps revert
/// with their own errors unwrapped. A handoff target's pipeline failure nests as `err`.
/// @param index Zero-based step index, matching the pipeline's Step and State records.
/// @param cmd Full command ID of the failing step, including its flags byte.
/// @param err Complete revert data returned by the failed call.
error StepFailed(uint index, uint cmd, bytes err);
