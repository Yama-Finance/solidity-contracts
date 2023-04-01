// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.18;

import "./YSSModule.sol";
import "../BalanceSheetModule.sol";

/// @notice Abstract contract for contracts that are part of the Yama Finance protocol.
abstract contract YSSModuleExtended is YSSModule {
  BalanceSheetModule public balanceSheet;

  /// @notice Sets the stablecoin and balance sheet
  /// @param _stablecoin Stablecoin to set
  /// @param _balanceSheet Balance sheet to set
  constructor(
    YSS _stablecoin, BalanceSheetModule _balanceSheet
  ) YSSModule(_stablecoin) {
    balanceSheet = _balanceSheet;
  }

  /// @notice Sets the balance sheet
  function setBalanceSheet(
    BalanceSheetModule _balanceSheet
  ) external onlyAllowlist {
    balanceSheet = _balanceSheet;
  }

}