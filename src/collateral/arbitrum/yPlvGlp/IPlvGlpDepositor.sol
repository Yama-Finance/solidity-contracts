// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.18;

/// @notice plvGLP depositor contract
interface IPlvGlpDepositor {
    function deposit(uint256 _amount) external;
    function redeem(uint256 _amount) external;
    function STAKER() external view returns (address);
}
