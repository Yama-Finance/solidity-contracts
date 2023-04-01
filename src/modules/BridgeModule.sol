// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.18;

import "./templates/GenericModule.sol";
import "../interfaces/IBridgeReceiver.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import {IInterchainGasPaymaster} from "@hyperlane-xyz/interfaces/IInterchainGasPaymaster.sol";
import {IMailbox} from "@hyperlane-xyz/interfaces/IMailbox.sol";
import {TypeCasts} from "@hyperlane-xyz/contracts/libs/TypeCasts.sol";

/// @notice Manages cross-chain Yama/GovToken transfers
/// @dev This is a GenericModule so it can be used with any ModularToken
contract BridgeModule is GenericModule {
  IMailbox public mailbox;
  // Interchain Gas Paymaster contract. The relayer associated with this contract
  // must be willing to relay messages dispatched from the current Outbox contract,
  // otherwise payments made to the paymaster will not result in relayed messages.
  IInterchainGasPaymaster public interchainGasPaymaster;

  uint8 public tokenDecimals;

  address public interchainSecurityModule;

  mapping(uint32 chainId => uint8 decimals) public chainDecimals;

  mapping(uint32 chainId => bytes32 bridge) public bridgeAddress;

  mapping(uint32 chainId => uint256 gas) public chainGas;

  mapping(uint32 chainId => mapping(bytes32 altBridge => bool isBridge)) public altBridgeAddress;

  /// @notice Emitted when a transfer is sent to a remote chain
  /// @param fromAddress The address of the sender on the current chain
  /// @param dstChainId The chain ID of the chain the tokens are being sent to
  /// @param toAddress The address of the recipient on the remote chain
  /// @param metadata Arbitrary metadata sent with the transfer (e.g. contract vs address on Fuel)
  /// @param amount The amount of tokens sent
  event RemoteTransferSent(
    address indexed fromAddress,
    uint32 indexed dstChainId,
    bytes32 indexed toAddress,
    uint32 metadata,
    uint256 amount
  );

  /// @notice Emitted when a transfer is received from a remote chain
  /// @param fromAddress The address of the sender on the chain the tokens were sent from
  /// @param srcChainId The chain ID of the chain the tokens were sent from
  /// @param toAddress The address of the recipient on the current chain
  /// @param amount The amount of tokens received
  event RemoteTransferReceived(
    bytes32 indexed fromAddress,
    uint32 indexed srcChainId,
    address indexed toAddress,
    uint256 amount
  );

  /// @notice Only accept messages from the Hyperlane mailbox contract
  modifier onlyMailbox() {
    require(msg.sender == address(mailbox), "!mailbox");
    _;
  }

  /// @notice Initializes the Hyperlane parameters for the bridge
  /// @param _mailbox The Hyperlane mailbox contract
  /// @param _interchainGasPaymaster The Hyperlane interchain gas paymaster contract
  /// @param _interchainSecurityModule The Hyperlane interchain security module contract
  constructor(
    ModularToken _token,
    uint8 _tokenDecimals,
    address _mailbox,
    address _interchainGasPaymaster,
    address _interchainSecurityModule
  ) GenericModule(_token) {
    tokenDecimals = _tokenDecimals;
    setHyperlaneParameters(
      _mailbox,
      _interchainGasPaymaster,
      _interchainSecurityModule
    );
  }

  /// @notice Transfers YSS from the sender's wallet to a remote chain
  /// @param dstChainId The Hyperlane chain identifier of the remote chain
  /// @param toAddress The recipient's address on the remote chain.
  /// @param amount Amount of YSS to send.
  /// @param receiverPayload An arbitrary payload sent to the recipient callback
  function transferRemote(
    uint32 dstChainId,
    bytes32 toAddress,
    uint32 metadata,
    uint256 amount,
    bytes calldata receiverPayload
  ) external {
    sendRemoteTransfer(
      msg.sender,
      dstChainId,
      toAddress,
      metadata,
      amount,
      receiverPayload
    );
  }

  /// @notice Calls the callback of an address receiving a cross-chain transfer
  /// @param receiver The address of the receiver
  /// @param origin The chain ID of the chain the tokens were sent from
  /// @param fromAddress The address of the sender on the chain the tokens were sent from
  /// @param amount The amount of tokens received
  /// @param receiverPayload An arbitrary payload sent to the recipient callback
  /// @dev This is called in a try statement
  function callBridgeReceiver(
    address receiver,
    uint32 origin,
    bytes32 fromAddress,
    uint256 amount,
    bytes calldata receiverPayload
  ) external {
    require(msg.sender == address(this));
    IBridgeReceiver(receiver).yamaBridgeCallback(
      origin, fromAddress, amount, receiverPayload
    );
  }

  /// @notice Handles a cross-chain transfer.
  /// @dev This is called by the Hyperlane mailbox contract
  /// @param origin The chain ID of the chain the tokens were sent from
  /// @param sender The address of the bridge contract on the chain the tokens were sent from
  /// @param payload The payload of the message
  function handle(
    uint32 origin,
    bytes32 sender,
    bytes calldata payload
  ) external onlyMailbox {
    require(sender == bridgeAddress[origin] || altBridgeAddress[origin][sender],
      "Bridge: Invalid source bridge");
    
    (
      bytes32 fromAddress,
      address toAddress,
      uint256 amount,
      bytes calldata receiverPayload
    ) = decodePayload(payload);

    token.mint(toAddress, amount);

    try this.callBridgeReceiver(
      toAddress,
      origin,
      fromAddress,
      amount,
      receiverPayload
    ) {} catch {}

    emit RemoteTransferReceived(
      fromAddress,
      origin,
      toAddress,
      amount
    );
  }

  /// @notice Sets the decimals of another chain
  /// @param chainId The Hyperlane chain identifier for the remote chain
  /// @param decimals The number of decimals of the remote chain
  function setDecimals(
    uint32 chainId,
    uint8 decimals
  ) external onlyAllowlist {
    chainDecimals[chainId] = decimals;
  }

  /// @notice Sets the address of a bridge contract on another chain.
  /// @param chainId The Hyperlane chain identifier for the remote chain
  /// @param _bridgeAddress The address of the bridge contract on the remote chain
  /// @dev Sends messages to and accepts messages from that address
  function setBridge(
    uint32 chainId,
    bytes32 _bridgeAddress
  ) external onlyAllowlist {
    bridgeAddress[chainId] = _bridgeAddress;
  }

  /// @notice Sets the gas price of a chain
  /// @param chainId The Hyperlane chain identifier for the remote chain
  /// @param _chainGas The gas price of the remote chain
  function setChainGas(
    uint32 chainId,
    uint256 _chainGas
  ) external onlyAllowlist {
    chainGas[chainId] = _chainGas;
  }

  /// @notice Sets an alternate remote bridge address to accept messages from
  /// @param chainId The Hyperlane chain identifier for the remote chain
  /// @param _altBridgeAddress The remote bridge address
  /// @param isAltBridge Whether this is a valid alternate remote bridge address
  function setAlternateBridge(
    uint32 chainId,
    bytes32 _altBridgeAddress,
    bool isAltBridge
  ) external onlyAllowlist{
    altBridgeAddress[chainId][_altBridgeAddress] = isAltBridge;
  }

  /// @notice Transfers YSS from the specified wallet to a remote chain
  /// @param fromAddress The wallet YSS is transferred from.
  /// @param dstChainId The Hyperlane chain identifier of the remote chain
  /// @param toAddress The recipient's address on the remote chain.
  /// @param amount Amount of YSS to send.
  /// @param receiverPayload An arbitrary payload sent to the recipient callback
  function transferFromRemote(
    address fromAddress,
    uint32 dstChainId,
    bytes32 toAddress,
    uint32 metadata,
    uint256 amount,
    bytes calldata receiverPayload
  ) external {
    uint256 allowance = token.allowance(fromAddress, msg.sender);
    require(allowance >= amount, "Bridge: Insufficient allowance");

    sendRemoteTransfer(
      fromAddress,
      dstChainId,
      toAddress,
      metadata,
      amount,
      receiverPayload
    );

    allowance -= amount;

    // Not the ERC20 approve function, so SafeERC20 not required.
    token.approve(fromAddress, msg.sender, allowance);
  }

  /// @notice Sets the Hyperlane parameters
  /// @param _mailbox The Hyperlane mailbox contract
  /// @param _interchainGasPaymaster The Hyperlane interchain gas paymaster contract
  /// @param _interchainSecurityModule The Hyperlane interchain security module contract
  function setHyperlaneParameters(
    address _mailbox,
    address _interchainGasPaymaster,
    address _interchainSecurityModule
  ) public onlyAllowlist {
    mailbox = IMailbox(_mailbox);
    interchainGasPaymaster = IInterchainGasPaymaster(_interchainGasPaymaster);
    interchainSecurityModule = _interchainSecurityModule;
  }

  /// @notice Encodes data to send with Hyperlane
  /// @param fromAddress The address of the sender
  /// @param toAddress The address of the recipient
  /// @param metadata Arbitrary metadata
  /// @param amount The amount of tokens to send
  /// @param toDecimals The number of decimals of the recipient chain
  /// @param receiverPayload An arbitrary payload sent to the recipient callback
  /// @return payload The encoded data
  function encodePayload(
    address fromAddress,
    bytes32 toAddress,
    uint32 metadata,
    uint256 amount,
    uint8 toDecimals,
    bytes calldata receiverPayload
  ) public view returns (bytes memory payload) {
    return abi.encodePacked(
      uint8(1),  // Version
      TypeCasts.addressToBytes32(fromAddress),
      toAddress,
      metadata,
      convertAmount(amount, tokenDecimals, toDecimals),
      receiverPayload
    );
  }

  /// @notice Decodes an encoded payload from Hyperlane
  /// @param payload The encoded payload
  /// @return fromAddress The address of the sender
  /// @return toAddress The address of the recipient
  /// @return amount The amount of tokens to send
  /// @return receiverPayload An arbitrary payload sent to the recipient callback
  function decodePayload(
    bytes calldata payload
  ) public pure returns (
    bytes32 fromAddress,
    address toAddress,
    uint256 amount,
    bytes calldata receiverPayload
  ) {
    require(uint8(payload[0]) == 1, "Bridge: Invalid payload");
    fromAddress = bytes32(payload[1:33]);
    toAddress = TypeCasts.bytes32ToAddress(bytes32(payload[33:65]));
    amount = uint256(bytes32(payload[69:101]));
    receiverPayload = payload[101:];
  }

  /// @notice Encodes cross-chain transfer data and sends it with Hyperlane
  /// @param fromAddress The wallet YSS is transferred from.
  /// @param dstChainId The Hyperlane chain identifier of the remote chain
  /// @param toAddress The recipient's address on the remote chain.
  /// @param amount Amount of YSS to send.
  /// @param receiverPayload An arbitrary payload sent to the recipient callback
  function sendRemoteTransfer(
    address fromAddress,
    uint32 dstChainId,
    bytes32 toAddress,
    uint32 metadata,
    uint256 amount,
    bytes calldata receiverPayload
  ) internal {
    token.burn(fromAddress, amount);

    bytes memory payload = encodePayload(
      fromAddress,
      toAddress,
      metadata,
      amount,
      chainDecimals[dstChainId],
      receiverPayload
    );

    bytes32 leafIndex = mailbox.dispatch(
      dstChainId,
      bridgeAddress[dstChainId],
      payload
    );
    
    interchainGasPaymaster.payForGas{value:msg.value}(
      leafIndex,
      dstChainId,
      chainGas[dstChainId],
      msg.sender
    );

    emit RemoteTransferSent(
      fromAddress,
      dstChainId,
      toAddress,
      metadata,
      amount
    );
  }
}
