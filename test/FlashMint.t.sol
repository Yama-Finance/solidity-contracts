// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.18;

import "forge-std/Test.sol";
import "src/modules/FlashMintModule.sol";
import "@openzeppelin/contracts/interfaces/IERC3156FlashLender.sol";

contract FlashMintTest is Test, IERC3156FlashBorrower {
  FlashMintModule flashMint;
  YSS stablecoin;

  uint256 amountMint;

  function setUp() public {
    stablecoin = new YSS();
    flashMint = new FlashMintModule(stablecoin, 10_000);
    stablecoin.setAllowlist(address(flashMint), true);
  }

  function executeFlashMint(
    uint256 amount,
    bool authorizeProperly,
    bool returnCorrectValue
  ) public {
    amountMint = amount;
    bytes memory data;
    if (authorizeProperly) {
      data = abi.encodePacked("1");
    } else {
      data = abi.encodePacked("0");
    }
    if (returnCorrectValue) {
      data = abi.encodePacked(data, "1");
    } else {
      data = abi.encodePacked(data, "0");
    }
    flashMint.flashLoan(
      IERC3156FlashBorrower(this),
      address(stablecoin),
      amount,
      data
    );
  }

  function testFlashMint() public {
    executeFlashMint(1000, true, true);
    assertEq(stablecoin.balanceOf(address(this)), 0);
    vm.expectRevert(bytes("Yama: Flash loan exceeds max"));
    executeFlashMint(10_001, true, true);
    vm.expectRevert(bytes("Yama: Insufficient allowance"));
    executeFlashMint(1000, false, true);
    vm.expectRevert(bytes("Yama: Callback failed"));
    executeFlashMint(1000, true, false);
  }

  function testMaxFlashLoan() public {
    assertEq(flashMint.maxFlashLoan(address(stablecoin)), 10_000);
    vm.expectRevert(bytes("Yama: Not YSS"));
    flashMint.maxFlashLoan(address(0));
  }

  function testFee() public {
    assertEq(flashMint.flashFee(address(stablecoin), 5000), 0);
  }

  function testSetMax() public {
    flashMint.setMax(100_000);
    assertEq(flashMint.maxFlashLoan(address(stablecoin)), 100_000);
  }

  function onFlashLoan(
        address initiator,
        address token,
        uint256 amount,
        uint256 fee,
        bytes calldata data
    ) external returns (bytes32) {
      token;
      initiator;
      if (data[0] == "1") {
        stablecoin.approve(address(flashMint), amount);
      }
      assert(fee == 0);
      assert(amount == amountMint);
      assert(stablecoin.balanceOf(address(this)) == amountMint);
      if (data[1] == "1") {
        return keccak256("ERC3156FlashBorrower.onFlashLoan");
      } else {
        return keccak256("Invalid return value");
      }
    }
}