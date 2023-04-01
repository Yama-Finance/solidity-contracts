// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.18;

/// @notice Performs actions with CDP collateral, such as re-lending.
interface ICollateralManager {
  /// @notice Called when collateral is deposited into a CDP.
  /// @param vaultId The CDP ID.
  /// @param amount The amount of collateral deposited.
  function handleCollateralDeposit(
    uint256 vaultId,
    uint256 amount
  ) external;

  /// @notice Called when collateral is withdrawn from a CDP.
  /// @param vaultId The CDP ID.
  /// @param amount The amount of collateral withdrawn.
  function handleCollateralWithdrawal(
    uint256 vaultId,
    uint256 amount
  ) external;
}