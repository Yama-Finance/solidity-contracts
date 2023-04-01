// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.18;

contract TestBSH {
    function onAddSurplus(int256 amount) external pure {
        require(amount > 0, "Zero amount");
    }

    function onAddDeficit(int256 amount) external pure {
        require(amount > 0, "Zero amount");
    }
}