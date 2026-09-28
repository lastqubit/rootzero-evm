// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

/// @dev Thrown when a low-level call or query fails.
/// @param addr Contract address that was called.
/// @param selector 4-byte selector of the called function.
/// @param err Revert data returned by the failed call.
error FailedCall(address addr, bytes4 selector, bytes err);

/// @notice Low-level calls and queries with a single bytes argument.
library Calls {
    /// @notice Call `addr` with `selector(data)` and report whether it succeeded.
    /// @dev Encodes memory `data` as the sole `bytes` argument and ignores returndata.
    /// The caller is responsible for authorization and selector/target validation.
    /// @param selector Selector of a function taking one `bytes` argument.
    /// @param addr Target contract address.
    /// @param value Native value to forward in wei.
    /// @param data Raw contents of the function's `bytes` argument.
    /// @return success True when the low-level call succeeded.
    function tryRaw(
        bytes4 selector,
        address addr,
        uint value,
        bytes memory data
    ) internal returns (bool success) {
        return tryRaw(selector, addr, value, gasleft(), data);
    }

    /// @notice Try a memory-backed call with an explicit gas budget.
    /// @dev Ignores returndata. The EVM caps forwarded gas under EIP-150 and adds
    /// the value-transfer stipend when value is nonzero. The caller must account
    /// for data copying, memory expansion and CALL overhead when reserving gas.
    /// The caller is responsible for authorization and selector/target validation.
    /// @param selector Selector of a function taking one `bytes` argument.
    /// @param addr Target contract address.
    /// @param value Native value to forward in wei.
    /// @param gasLimit Requested CALL gas, excluding the value-transfer stipend.
    /// @param data Raw contents of the function's `bytes` argument.
    /// @return success True when the low-level call succeeded.
    function tryRaw(
        bytes4 selector,
        address addr,
        uint value,
        uint gasLimit,
        bytes memory data
    ) internal returns (bool success) {
        assembly ("memory-safe") {
            let scratch := mload(0x40)
            let len := mload(data)
            let body := add(scratch, 0x44)
            mstore(scratch, selector)
            mstore(add(scratch, 0x04), 0x20)
            mstore(add(scratch, 0x24), len)
            mcopy(body, add(data, 0x20), len)
            mstore(add(body, len), 0)
            success := call(gasLimit, addr, value, scratch, add(0x44, and(add(len, 0x1f), not(0x1f))), 0, 0)
        }
    }

    /// @notice Call `addr` with `selector(data)` copied from calldata and report success.
    /// @dev Encodes the calldata cursor as the sole `bytes` argument without an intermediate
    /// memory copy and ignores returndata. The caller is responsible for authorization
    /// and selector/target validation.
    /// Requires current <= end <= calldatasize; ignores metadata and does not advance the cursor.
    /// @param selector Selector of a function taking one `bytes` argument.
    /// @param addr Target contract address.
    /// @param value Native value to forward in wei.
    /// @param dataCur Validated calldata cursor over the raw contents of the function's `bytes` argument.
    /// @return success True when the low-level call succeeded.
    function tryRaw(
        bytes4 selector,
        address addr,
        uint value,
        uint dataCur
    ) internal returns (bool success) {
        return tryRaw(selector, addr, value, gasleft(), dataCur);
    }

    /// @notice Try a calldata-backed call with an explicit gas budget.
    /// @dev Ignores returndata. The EVM caps forwarded gas under EIP-150 and adds
    /// the value-transfer stipend when value is nonzero. The caller must account
    /// for data copying, memory expansion and CALL overhead when reserving gas.
    /// The caller is responsible for authorization and selector/target validation.
    /// Requires current <= end <= calldatasize; ignores metadata and does not advance the cursor.
    /// @param selector Selector of a function taking one `bytes` argument.
    /// @param addr Target contract address.
    /// @param value Native value to forward in wei.
    /// @param gasLimit Requested CALL gas, excluding the value-transfer stipend.
    /// @param dataCur Validated calldata cursor over the raw contents of the function's `bytes` argument.
    /// @return success True when the low-level call succeeded.
    function tryRaw(
        bytes4 selector,
        address addr,
        uint value,
        uint gasLimit,
        uint dataCur
    ) internal returns (bool success) {
        assembly ("memory-safe") {
            let scratch := mload(0x40)
            let abs := and(dataCur, 0xffffffff)
            let len := sub(and(shr(32, dataCur), 0xffffffff), abs)
            let body := add(scratch, 0x44)

            mstore(scratch, selector)
            mstore(add(scratch, 0x04), 0x20)
            mstore(add(scratch, 0x24), len)
            calldatacopy(body, abs, len)
            mstore(add(body, len), 0)

            let padded := and(add(len, 0x1f), not(0x1f))
            success := call(gasLimit, addr, value, scratch, add(0x44, padded), 0, 0)
        }
    }

    /// @notice Call `addr` with `selector(data)` and return its decoded `(bytes, uint)` result.
    /// @dev Encodes memory `data` as the sole `bytes` argument, reverts with `FailedCall`
    /// on call failure, and rejects invalid successful `(bytes, uint)` returndata. The caller
    /// is responsible for authorization and selector/target validation.
    /// @param selector Selector of a `bytes -> (bytes, uint)` port.
    /// @param addr Target contract address.
    /// @param value Native value to forward in wei.
    /// @param data Raw contents of the function's `bytes` argument.
    /// @param expectEmpty Whether the decoded result must be empty.
    /// @return out Decoded output bytes returned by the target.
    /// @return credit Trusted native budget credit. No ETH is transferred back by this helper.
    /// The caller must ensure backing is available before adding credit to its budget.
    function raw(
        bytes4 selector,
        address addr,
        uint value,
        bytes memory data,
        bool expectEmpty
    ) internal returns (bytes memory out, uint credit) {
        bool success;
        assembly ("memory-safe") {
            let scratch := mload(0x40)
            let len := mload(data)
            let body := add(scratch, 0x44)
            mstore(scratch, selector)
            mstore(add(scratch, 0x04), 0x20)
            mstore(add(scratch, 0x24), len)
            mcopy(body, add(data, 0x20), len)
            mstore(add(body, len), 0)
            success := call(gas(), addr, value, scratch, add(0x44, and(add(len, 0x1f), not(0x1f))), 0, 0)

            let size := returndatasize()
            switch success
            case 0 {
                // Failure needs a bytes wrapper for FailedCall's raw revert data.
                out := scratch
                mstore(out, size)
                returndatacopy(add(out, 0x20), 0, size)
                mstore(add(add(out, 0x20), size), 0)
                mstore(0x40, and(add(add(add(out, 0x20), size), 0x1f), not(0x1f)))
            }
            default {
                // Successful ABI returndata already contains the bytes length word.
                let encoded := scratch
                returndatacopy(encoded, 0, size)
                if or(lt(size, 0x60), iszero(eq(mload(encoded), 0x40))) {
                    revert(0, 0)
                }
                credit := mload(add(encoded, 0x20))
                let outputLen := mload(add(encoded, 0x40))
                if and(expectEmpty, iszero(iszero(outputLen))) {
                    revert(0, 0)
                }
                let padded := and(add(outputLen, 0x1f), not(0x1f))
                if or(gt(outputLen, sub(size, 0x60)), iszero(eq(size, add(0x60, padded)))) {
                    revert(0, 0)
                }
                out := add(encoded, 0x40)
                // Validated ABI size is word-aligned; reserve exactly the copied data.
                mstore(add(scratch, size), 0)
                mstore(0x40, add(scratch, size))
            }
        }
        if (!success) revert FailedCall(addr, selector, out);
    }

    /// @notice Call `addr` with `selector(data)` copied from calldata and return decoded output and credit.
    /// @dev Encodes the calldata cursor as the sole `bytes` argument without an intermediate
    /// memory copy, reverts with `FailedCall` on call failure, and rejects invalid
    /// successful `(bytes, uint)` returndata. The caller is responsible for authorization and
    /// selector/target validation.
    /// Requires current <= end <= calldatasize; ignores metadata and does not advance the cursor.
    /// @param selector Selector of a `bytes -> (bytes, uint)` port.
    /// @param addr Target contract address.
    /// @param value Native value to forward in wei.
    /// @param dataCur Validated calldata cursor over the raw contents of the function's `bytes` argument.
    /// @param expectEmpty Whether the decoded result must be empty.
    /// @return out Decoded output bytes returned by the target.
    /// @return credit Trusted native budget credit. No ETH is transferred back by this helper.
    /// The caller must ensure backing is available before adding credit to its budget.
    function raw(
        bytes4 selector,
        address addr,
        uint value,
        uint dataCur,
        bool expectEmpty
    ) internal returns (bytes memory out, uint credit) {
        bool success;
        assembly ("memory-safe") {
            let scratch := mload(0x40)
            let abs := and(dataCur, 0xffffffff)
            let len := sub(and(shr(32, dataCur), 0xffffffff), abs)
            let body := add(scratch, 0x44)
            mstore(scratch, selector)
            mstore(add(scratch, 0x04), 0x20)
            mstore(add(scratch, 0x24), len)
            calldatacopy(body, abs, len)
            mstore(add(body, len), 0)
            success := call(gas(), addr, value, scratch, add(0x44, and(add(len, 0x1f), not(0x1f))), 0, 0)

            let size := returndatasize()
            switch success
            case 0 {
                // Failure needs a bytes wrapper for FailedCall's raw revert data.
                out := scratch
                mstore(out, size)
                returndatacopy(add(out, 0x20), 0, size)
                mstore(add(add(out, 0x20), size), 0)
                mstore(0x40, and(add(add(add(out, 0x20), size), 0x1f), not(0x1f)))
            }
            default {
                // Successful ABI returndata already contains the bytes length word.
                let encoded := scratch
                returndatacopy(encoded, 0, size)
                if or(lt(size, 0x60), iszero(eq(mload(encoded), 0x40))) {
                    revert(0, 0)
                }
                credit := mload(add(encoded, 0x20))
                let outputLen := mload(add(encoded, 0x40))
                if and(expectEmpty, iszero(iszero(outputLen))) {
                    revert(0, 0)
                }
                let padded := and(add(outputLen, 0x1f), not(0x1f))
                if or(gt(outputLen, sub(size, 0x60)), iszero(eq(size, add(0x60, padded)))) {
                    revert(0, 0)
                }
                out := add(encoded, 0x40)
                // Validated ABI size is word-aligned; reserve exactly the copied data.
                mstore(add(scratch, size), 0)
                mstore(0x40, add(scratch, size))
            }
        }
        if (!success) revert FailedCall(addr, selector, out);
    }

    /// @notice Query `addr` with `selector(data)` and return its decoded `bytes` result.
    /// @dev Encodes memory `data` as the sole `bytes` argument, reverts with `FailedCall`
    /// on query failure, and rejects invalid successful `bytes` returndata. The caller
    /// is responsible for authorization and selector/target validation.
    /// @param selector Selector of a `bytes -> bytes` function.
    /// @param addr Target contract address.
    /// @param data Raw contents of the function's `bytes` argument.
    /// @return out Decoded `bytes` returned by the target.
    function rawQuery(
        bytes4 selector,
        address addr,
        bytes memory data
    ) internal view returns (bytes memory out) {
        bool success;
        assembly ("memory-safe") {
            let scratch := mload(0x40)
            let len := mload(data)
            let body := add(scratch, 0x44)
            mstore(scratch, selector)
            mstore(add(scratch, 0x04), 0x20)
            mstore(add(scratch, 0x24), len)
            mcopy(body, add(data, 0x20), len)
            mstore(add(body, len), 0)
            success := staticcall(gas(), addr, scratch, add(0x44, and(add(len, 0x1f), not(0x1f))), 0, 0)

            let size := returndatasize()
            switch success
            case 0 {
                // Failure needs a bytes wrapper for FailedCall's raw revert data.
                out := scratch
                mstore(out, size)
                returndatacopy(add(out, 0x20), 0, size)
                mstore(add(add(out, 0x20), size), 0)
                mstore(0x40, and(add(add(add(out, 0x20), size), 0x1f), not(0x1f)))
            }
            default {
                // Successful ABI returndata already contains the bytes length word.
                let encoded := scratch
                returndatacopy(encoded, 0, size)
                if or(lt(size, 0x40), iszero(eq(mload(encoded), 0x20))) {
                    revert(0, 0)
                }
                let outputLen := mload(add(encoded, 0x20))
                let padded := and(add(outputLen, 0x1f), not(0x1f))
                if or(gt(outputLen, sub(size, 0x40)), iszero(eq(size, add(0x40, padded)))) {
                    revert(0, 0)
                }
                out := add(encoded, 0x20)
                // Validated ABI size is word-aligned; reserve exactly the copied data.
                mstore(add(scratch, size), 0)
                mstore(0x40, add(scratch, size))
            }
        }
        if (!success) revert FailedCall(addr, selector, out);
    }
}
