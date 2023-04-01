// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.18;

import "src/modules/templates/YSSModuleExtended.sol";
import "src/interfaces/IBalanceSheetHandler.sol";

/// @notice Whenever there is surplus, SimpleBSH gives part of it to the target address
contract SimpleBSH is YSSModuleExtended, IBalanceSheetHandler {
  /// @notice The address receiving part of the surplus
  address public immutable target;
  
  uint256 public revenueShare;
  uint256 public constant DENOMINATOR = 10000;
  uint256 public lastBlockUpdate;
  uint256 public pendingShareAmount;

  /// @notice Sets the stablecoin, balance sheet, revenue share and target
  /// @param _stablecoin Stablecoin to set
  /// @param _balanceSheet Balance sheet to set
  /// @param _revenueShare Revenue share to set
  /// @param _target Target to set
  constructor(
    YSS _stablecoin,
    BalanceSheetModule _balanceSheet,
    uint256 _revenueShare,
    address _target
  )
    YSSModuleExtended(_stablecoin, _balanceSheet)
  {
    revenueShare = _revenueShare;
    target = _target;
  }

  /// @notice Sets the revenue share
  /// @param _revenueShare Revenue share to set
  function setRevenueShare(uint256 _revenueShare) external onlyAllowlist {
    require(_revenueShare <= DENOMINATOR, "SimpleBSH: Exceeds denominator");
    revenueShare = _revenueShare;
  }

  /// @notice Give part of the surplus to the target address
  /// @param amount The surplus amount.
  function onAddSurplus(int256 amount) external {
    require(msg.sender == address(balanceSheet), "SimpleBSH: Only balance sheet");
    processPendingShareAmount();
    if (amount > 0) {
      uint256 shareAmount = uint256(amount) * revenueShare / DENOMINATOR;
      pendingShareAmount += shareAmount;
      balanceSheet.addDeficit(int256(shareAmount));
    }
  }

  /// @notice Does nothing on deficit
  /// @param amount The deficit amount.
  function onAddDeficit(int256 amount) external {}

  /// @notice Processes the pending share amount
  function processPendingShareAmount() public {
    if (block.number > lastBlockUpdate) {
      stablecoin.mint(
        target,
        pendingShareAmount
      );
      pendingShareAmount = 0;
      lastBlockUpdate = block.number;
    }
  }
}