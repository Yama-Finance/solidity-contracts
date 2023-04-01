// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.18;

import "../../YSS.sol";
import "./Module.sol";

/// @notice Abstract contract to easily check if caller is on the YSS's allowlist
abstract contract YSSModule is Module {
  YSS public stablecoin;
  
  /// @notice Modifier to check if caller is on the allowlist
  modifier onlyAllowlist() {
    require(stablecoin.allowlist(msg.sender));
    _;
  }

  /// @notice Sets the token
  /// @param _stablecoin Token to set
  constructor(YSS _stablecoin) {
    stablecoin = _stablecoin;
  }
}