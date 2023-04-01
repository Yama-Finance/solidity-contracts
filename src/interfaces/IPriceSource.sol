// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.18;

/// @notice Returns the price of a collateral type in Yama.
/// @dev Used by the CDP module to determine the value of collateral.
interface IPriceSource {
  /// @notice Returns the price of a collateral type in Yama.
  /// @return amount price of the collateral type in Yama.
  function price() external view returns (uint256 amount);
}
