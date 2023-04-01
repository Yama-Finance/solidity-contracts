// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.18;

import "../modules/templates/YSSModuleExtended.sol";

/// @notice Manages donations to the Yama protocol.
contract DonationManager is YSSModuleExtended {
    constructor(
        YSS _stablecoin,
        BalanceSheetModule _balanceSheet
    ) YSSModuleExtended(_stablecoin, _balanceSheet) {
        stablecoin = _stablecoin;
        balanceSheet = _balanceSheet;
    }

    /// @notice Donates money to the Yama protocol.
    /// @param amount The amount to donate.
    function donate(uint256 amount) external onlyAllowlist {
        stablecoin.burn(msg.sender, amount);
        balanceSheet.setSurplus(balanceSheet.totalSurplus() + int256(amount));
    }
}