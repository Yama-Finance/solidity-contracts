// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.18;

/// @notice Called when a protocol surplus or deficit is registered.
interface IBalanceSheetHandler {

  /// @notice Called when a protocol surplus is registered.
  /// @param amount The surplus amount.
  function onAddSurplus(int256 amount) external;

  /// @notice Called when a protocol deficit is registered.
  /// @param amount The deficit amount.
  function onAddDeficit(int256 amount) external;
}