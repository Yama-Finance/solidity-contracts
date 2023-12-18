// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.18;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @notice A Plutus yield farm
interface IPlutusChef {
    function deposit(uint96 _amount) external;
    function withdraw(uint96 _amount) external;
    function emergencyWithdraw() external;
    function harvest() external;
    function userInfo(
        address _user
    ) external view returns (uint96 amount, int128 plsRewardDebt);
    function pendingRewards(address _user) external view returns (uint256);
}