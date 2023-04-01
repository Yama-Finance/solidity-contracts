// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.18;

contract TestLiquidator {
    function liquidate(uint256 vaultId) external pure returns (bool) {
        return vaultId > 0;
    }
}