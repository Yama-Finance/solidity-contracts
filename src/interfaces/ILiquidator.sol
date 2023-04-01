// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.18;

/// @notice A contract the CDP calls to liquidate undercollateralized vaults.
interface ILiquidator {
  /// @notice Liquidates a CDP.
  /// @param vaultId The CDP vault ID.
  /// @return successful True if the liquidator accepts this liquidation.
  function liquidate(uint256 vaultId) external returns (bool successful);
}