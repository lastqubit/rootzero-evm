// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

import {Keys} from "../codec/Keys.sol";

/// @dev Frozen v1.51 scalar BALANCE logger for historical benchmark fixtures.
library LogsBalance151 {
    /// @notice Create and emit one full-width BALANCE block preceded by codes using LOG0.
    /// @dev Uses 104 temporary bytes at the free-memory pointer without advancing it.
    /// Preserves allocated memory; scratch contents are unspecified. No existing
    /// writer or owned prefix is required. Emits 104 bytes: 32-byte codes
    /// followed by the 72-byte BALANCE block, with no topics or additional format tag.
    /// Emits no account. The emitter defines whether amount is a delta or a resulting balance.
    /// @param asset Full-width asset identifier, encoded unchanged.
    /// @param amount Full-width quantity, encoded unchanged.
    /// @param codes Full uint256 descriptive code word, emitted unchanged.
    function balance(bytes32 asset, uint amount, uint codes) internal {
        uint key = uint32(Keys.Balance);
        assembly ("memory-safe") {
            let start := mload(0x40)
            mstore(start, codes)
            mstore(add(start, 32), or(shl(224, key), shl(192, 64)))
            mstore(add(start, 40), asset)
            mstore(add(start, 72), amount)
            log0(start, 104)
        }
    }

}
