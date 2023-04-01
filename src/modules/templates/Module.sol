// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.18;

/// @notice Provides a utility function for converting amounts between tokens with different decimal places.
abstract contract Module {
  /// @notice Converts an amount between tokens with different decimal places
  /// @param amount The amount to convert
  /// @param fromDecimals The number of decimals of the token to convert from
  /// @param toDecimals The number of decimals of the token to convert to
  /// @return result The converted amount
  function convertAmount(
    uint256 amount, uint8 fromDecimals, uint8 toDecimals
  ) internal pure returns (uint256 result) {
    if (fromDecimals == toDecimals) {
      return amount;
    } else if (fromDecimals < toDecimals) {
      return amount * (10 ** (toDecimals - fromDecimals));
    } else {
      return amount / (10 ** (fromDecimals - toDecimals));
    }
  }
}