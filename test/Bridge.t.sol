// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.18;

import "forge-std/Test.sol";
import "src/modules/BridgeModule.sol";
import "src/YSS.sol";
import "./test-contracts/TestMailbox.sol";
import "./test-contracts/TestInterchainGasPaymaster.sol";

contract BridgeTest is Test {
  YSS stablecoin;
  BridgeModule bridge;
  TestMailbox mailbox;
  TestInterchainGasPaymaster igp;
  uint256 public constant MAX_UINT
    = 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff;

  bytes lastReceivedPayload;

  function setUp() public {
    stablecoin = new YSS();
    mailbox = new TestMailbox();
    igp = new TestInterchainGasPaymaster();
    bridge = new BridgeModule(
      ModularToken(stablecoin),
      stablecoin.decimals(),
      address(mailbox),
      address(igp),
      address(0)
    );
    bridge.setBridge(
      0,
      TypeCasts.addressToBytes32(address(bridge))
    );
    bridge.setDecimals(
      0,
      stablecoin.decimals()
    );
    stablecoin.setAllowlist(address(bridge), true);
  }

  modifier assumeValidAddress(bytes32 encodedAddress) {
    vm.assume(encodedAddress == TypeCasts.addressToBytes32(
      TypeCasts.bytes32ToAddress(encodedAddress)));
    _;
  }

  function testBridgeTransfer() public {
    stablecoin.mint(address(this), 1000);
    bridge.transferRemote(
      0,
      TypeCasts.addressToBytes32(address(this)),
      0,
      1000,
      bytes("0x10")
    );

    assertEq(lastReceivedPayload, bytes("0x10"));
    assertEq(stablecoin.balanceOf(address(this)), 1000);
  }

  function testBridgeTransferFrom() public {
    stablecoin.mint(address(this), 1000);
    stablecoin.approve(address(1), 1000);
    vm.prank(address(1));
    bridge.transferFromRemote(
      address(this),
      0,
      TypeCasts.addressToBytes32(address(this)),
      0,
      1000,
      bytes("0x10")
    );

    assertEq(lastReceivedPayload, bytes("0x10"));
    assertEq(stablecoin.balanceOf(address(this)), 1000);
  }

  function testBridgeTransferFromInsufficientAllowance() public {
    stablecoin.mint(address(this), 1000);
    stablecoin.approve(address(1), 999);
    vm.prank(address(1));
    vm.expectRevert(bytes("Bridge: Insufficient allowance"));
    bridge.transferFromRemote(
      address(this),
      0,
      TypeCasts.addressToBytes32(address(this)),
      0,
      1000,
      bytes("0x10")
    );
  }

  function testCallBridgeReceiver() public {
    vm.expectRevert();
    bridge.callBridgeReceiver(
      address(0),
      0,
      TypeCasts.addressToBytes32(address(this)),
      0,
      bytes("")
    );
  }

  function testSenderNotBridge(
    address fromAddress,
    uint256 amount,
    bytes calldata receiverPayload
  ) public {
    bytes memory payload = bridge.encodePayload(
      fromAddress,
      TypeCasts.addressToBytes32(address(this)),
      0,
      amount,
      stablecoin.decimals(),
      receiverPayload
    );
    bridge.setBridge(0, bytes32(bytes("")));
    vm.expectRevert(bytes("Bridge: Invalid source bridge"));
    mailbox.proxyHandle(address(bridge), 0, bytes32(bytes("0x1a")), payload);

    bridge.setAlternateBridge(0, bytes32(bytes("0x1a")), true);
    mailbox.proxyHandle(address(bridge), 0, bytes32(bytes("0x1a")), payload);
  }

  function testInvalidVersionCode(
    address fromAddress,
    uint256 amount,
    bytes calldata receiverPayload
  ) public {
    bytes memory payload = bridge.encodePayload(
      fromAddress,
      TypeCasts.addressToBytes32(address(this)),
      0,
      amount,
      stablecoin.decimals(),
      receiverPayload
    );
    payload[0] = 0x00;
    bridge.setBridge(0, bytes32(bytes("")));
    vm.expectRevert(bytes("Bridge: Invalid payload"));
    mailbox.proxyHandle(address(bridge), 0, bytes32(bytes("")), payload);
  }

  function testEncodeDecode(
    address fromAddress,
    bytes32 toAddress,
    uint256 amount,
    bytes calldata receiverPayload
  ) public assumeValidAddress(toAddress) {
    vm.assume(amount < (MAX_UINT / 100));

    bytes memory payload = bridge.encodePayload(
      fromAddress,
      toAddress,
      0,
      amount,
      stablecoin.decimals() + 1,
      receiverPayload
    );

    (
      bytes32 fromAddressDecoded,
      address toAddressDecoded,
      uint256 amountDecoded,
      bytes memory receiverPayloadDecoded
    ) = bridge.decodePayload(payload);

    assertEq(TypeCasts.bytes32ToAddress(fromAddressDecoded), fromAddress);
    assertEq(toAddress, TypeCasts.addressToBytes32(toAddressDecoded));
    assertEq(amount * 10, amountDecoded);
    assertEq(abi.encodePacked(receiverPayload), receiverPayloadDecoded);
  }

  function testReceiverPayload(
    address fromAddress,
    uint256 amount,
    bytes calldata receiverPayload
  ) public {
    bytes memory payload = bridge.encodePayload(
      fromAddress,
      TypeCasts.addressToBytes32(address(this)),
      0,
      amount,
      stablecoin.decimals(),
      receiverPayload
    );
    bridge.setBridge(0, bytes32(bytes("")));
    mailbox.proxyHandle(address(bridge), 0, bytes32(bytes("")), payload);

    assertEq(stablecoin.balanceOf(address(this)), amount);

    assertEq(lastReceivedPayload, receiverPayload);
  }

  function testDecimals(
    uint256 amount,
    bytes calldata receiverPayload
  ) public {
    vm.assume(amount < type(uint256).max / 10);
    bridge.setDecimals(0, stablecoin.decimals() + 1);
    stablecoin.mint(address(this), amount);
    bridge.transferRemote(
      0,
      TypeCasts.addressToBytes32(address(this)),
      0,
      amount,
      receiverPayload
    );

    assertEq(stablecoin.balanceOf(address(this)), amount * 10);
  }

  function testSetHyperlaneParameters(
    uint256 amount,
    bytes calldata receiverPayload
  ) public {
    vm.assume(amount < type(uint256).max / 10);
    stablecoin.mint(address(this), amount);
    bridge.setHyperlaneParameters(
      address(mailbox),
      address(igp),
      address(0)
    );
    bridge.transferRemote(
      0,
      TypeCasts.addressToBytes32(address(this)),
      0,
      amount,
      receiverPayload
    );

    assertEq(stablecoin.balanceOf(address(this)), amount);
  }

  function testGas(
    uint256 amount,
    bytes calldata receiverPayload
  ) public {
    vm.assume(amount < type(uint256).max / 10);
    bridge.setChainGas(0, 1000000);
    stablecoin.mint(address(this), amount);
    bridge.transferRemote(
      0,
      TypeCasts.addressToBytes32(address(this)),
      0,
      amount,
      receiverPayload
    );

    assertEq(igp.lastGas(), 1000000);
  }

  function testInvalidReceiver(
    address fromAddress,
    address toAddress,
    uint256 amount,
    bytes calldata receiverPayload
  ) public {
    vm.assume(toAddress != address(0));
    bytes memory payload = bridge.encodePayload(
      fromAddress,
      TypeCasts.addressToBytes32(toAddress),
      0,
      amount,
      stablecoin.decimals(),
      receiverPayload
    );
    bridge.setBridge(0, bytes32(""));
    mailbox.proxyHandle(address(bridge), 0, bytes32(""), payload);
  }

  function yamaBridgeCallback(
    uint32 srcChainId,
    bytes32 fromAddress,
    uint256 amount,
    bytes calldata payload
  ) external {
    srcChainId = 0;
    fromAddress = bytes32("");
    amount = 0;
    lastReceivedPayload = payload;
  }

}
