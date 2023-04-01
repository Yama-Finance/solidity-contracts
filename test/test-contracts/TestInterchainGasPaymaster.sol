// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.18;

contract TestInterchainGasPaymaster {
  uint256 public lastGas;

  function payForGas(
        bytes32 _messageId,
        uint32 _destinationDomain,
        uint256 _gas,
        address _refundAddress
    ) external payable {
      lastGas = _gas;
      _destinationDomain;
      _refundAddress;
      _messageId;
    }
}