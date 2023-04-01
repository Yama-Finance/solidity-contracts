// SPDX-License-Identifier: MIT OR Apache-2.0
pragma solidity >=0.6.11;

// Library for building bytecode of minimal proxies (see https://eips.ethereum.org/EIPS/eip-1167)
library MinimalProxy {
    bytes20 constant PREFIX = hex"3d602d80600a3d3981f3363d3d373d3d3d363d73";
    bytes15 constant SUFFIX = hex"5af43d82803e903d91602b57fd5bf3";

    function bytecode(address implementation)
        internal
        pure
        returns (bytes memory)
    {
        return abi.encodePacked(PREFIX, bytes20(implementation), SUFFIX);
    }
}
