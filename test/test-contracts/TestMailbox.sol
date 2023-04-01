// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.18;

import "src/modules/BridgeModule.sol";
import {TypeCasts} from "@hyperlane-xyz/contracts/libs/TypeCasts.sol";
import {IMessageRecipient} from "@hyperlane-xyz/interfaces/IMessageRecipient.sol";

contract TestMailbox {
  function proxyHandle (
    address recipient,
    uint32 origin,
    bytes32 sender,
    bytes calldata payload
  ) external {
    IMessageRecipient(recipient).handle(origin, sender, payload);
  }

  function dispatch(
    uint32 dstChainId,
    bytes32 dstAddress,
    bytes calldata payload
  ) external returns (bytes32) {
    BridgeModule(TypeCasts.bytes32ToAddress(dstAddress)).handle(
      0,
      TypeCasts.addressToBytes32(msg.sender),
      payload
    );
    dstChainId = 0;
    return 0;
  }
}