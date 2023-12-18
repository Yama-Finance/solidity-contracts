// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.18;

import "src/interfaces/ICollateralManager.sol";

/// @notice A collateral manager that does nothing.
contract EmptyCollateralManager is ICollateralManager {
  /// @notice Called when collateral is deposited into a CDP and does nothing.
  function handleCollateralDeposit(
    uint256 vaultId,
    uint256 amount
  ) external pure {}

  /// @notice Called when collateral is withdrawn from a CDP and does nothing.
  function handleCollateralWithdrawal(
    uint256 vaultId,
    uint256 amount
  ) external pure {}
}