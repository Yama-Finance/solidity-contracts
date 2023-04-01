// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.18;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @notice Interface for a contract that can swap between Yama and a collateral token
interface ISwapper {
    /// @notice Swaps the collateral token to Yama
    /// @dev minOutputAmount is used to prevent sandwich attacks
    /// @param collateralAmount The amount of collateral to swap
    /// @param minOutputAmount The minimum amount of Yama to receive
    /// @return outputAmount The amount of Yama received
    function swapToYama(
        uint256 collateralAmount,
        uint256 minOutputAmount
    ) external returns (uint256 outputAmount);

    /// @notice Swaps Yama to the collateral token
    /// @dev minOutputAmount is used to prevent sandwich attacks
    /// @param yamaAmount The amount of Yama to swap
    /// @param minOutputAmount The minimum amount of collateral to receive
    /// @return outputAmount The amount of collateral received
    function swapToCollateral(
        uint256 yamaAmount,
        uint256 minOutputAmount
    ) external returns (uint256 outputAmount);
}