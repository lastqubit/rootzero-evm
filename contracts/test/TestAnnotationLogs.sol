// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

import {Logs} from "../codec/Logs.sol";
import {Codes} from "../utils/Codes.sol";

contract TestAnnotationLogs {
    function publish(uint entity, bytes memory data) external returns (bytes memory) {
        Logs.annotation(entity, data, Codes.HostAnnotate);
        return data;
    }
    function measure(uint entity, bytes memory data) external returns (uint used) {
        uint initial = gasleft();
        Logs.annotation(entity, data, Codes.HostAnnotate);
        used = initial - gasleft();
    }
}

// Frozen ABI format for migration gas comparisons only.
contract PreviousAnnotationLog {
    event Annotation(uint indexed entity, bytes data);
    function measure(uint entity, bytes memory data) external returns (uint used) {
        uint initial = gasleft();
        emit Annotation(entity, data);
        used = initial - gasleft();
    }
}
