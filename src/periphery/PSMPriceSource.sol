// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.18;

import "src/interfaces/IPriceSource.sol";
import "@prb/math/contracts/PRBMathUD60x18.sol";

/// @notice A price source that always returns a price of $1.
contract PSMPriceSource is IPriceSource {
  /// @notice Returns 1 Yama as the price of this collateral.
  function price() external pure returns (uint256) {
    return PRBMathUD60x18.SCALE;
  }
}