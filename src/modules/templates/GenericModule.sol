// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.18;

import "../../ModularToken.sol";
import "./Module.sol";

/// @notice Abstract contract to easily check if caller is on the token's allowlist
abstract contract GenericModule is Module {
  ModularToken public token;

  /// @notice Modifier to check if caller is on the allowlist
  modifier onlyAllowlist() {
    require(token.allowlist(msg.sender));
    _;
  }

  /// @notice Sets the token
  /// @param _token Token to set
  constructor(ModularToken _token) {
    token = _token;
  }
}