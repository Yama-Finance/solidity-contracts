// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.18;

import "./templates/YSSModule.sol";
import "../interfaces/IBalanceSheetHandler.sol";

/// @notice Keeps track of protocol deficit/surplus.
contract BalanceSheetModule is YSSModule {

  /// @notice The protocol surplus.
  int256 public totalSurplus;

  /// @notice Called when a protocol surplus or deficit is registered.
  IBalanceSheetHandler public handler;

  /// @notice Emitted when a protocol surplus is registered.
  /// @param account The account that registered the surplus.
  /// @param amount The surplus amount.
  event AddSurplus(address indexed account, int256 amount);

  /// @notice Emitted when a protocol deficit is registered.
  /// @param account The account that registered the deficit.
  /// @param amount The deficit amount.
  event AddDeficit(address indexed account, int256 amount);

  /// @notice Emitted when the protocol surplus is set.
  /// @param account The account that set the surplus.
  event SetSurplus(address indexed account, int256 amount);

  /// @notice Sets the stablecoin address
  constructor(YSS _stablecoin) YSSModule(_stablecoin) {}

  /// @notice Sets the handler
  /// @param _handler Handler to set
  function setHandler(IBalanceSheetHandler _handler) external onlyAllowlist {
    handler = _handler;
  }

  /// @notice Registers a protocol surplus
  /// @param amount The surplus amount.
  function addSurplus(int256 amount) external onlyAllowlist {
    totalSurplus += amount;
    emit AddSurplus(msg.sender, amount);
    if (address(handler) != address(0)) {
      handler.onAddSurplus(amount);
    }
  }

  /// @notice Registers a protocol deficit
  /// @param amount The deficit amount.
  function addDeficit(int256 amount) external onlyAllowlist {
    totalSurplus -= amount;
    emit AddDeficit(msg.sender, amount);
    if (address(handler) != address(0)) {
      handler.onAddDeficit(amount);
    }
  }

  /// @notice Sets the protocol surplus
  /// @param amount The surplus amount.
  function setSurplus(int256 amount) external onlyAllowlist {
    totalSurplus = amount;
    emit SetSurplus(msg.sender, amount);
  }
}