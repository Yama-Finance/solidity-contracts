// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.18;

/// @notice A contract that receives bridged YSS/YAMA tokens
interface IBridgeReceiver {
  /// @notice Executes upon receiving bridged YSS/YAMA tokens
  /// @param srcChainId The chain ID of the chain the tokens were bridged from
  /// @param fromAddress The address of the sender on the chain the tokens were bridged from
  /// @param amount The amount of tokens received
  /// @param payload The payload data sent with the tokens
  /// @dev Make sure to check the YSS/YAMA bridge module is msg.sender
  /// @dev This is the same callback for the YAMA and YSS bridge.
  function yamaBridgeCallback(
    uint32 srcChainId,
    bytes32 fromAddress,
    uint256 amount,
    bytes calldata payload
  ) external;
}