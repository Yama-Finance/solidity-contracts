// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.18;

import "forge-std/Test.sol";
import "src/modules/PegStabilityModule.sol";

contract PegStabilityModuleTest is Test {
  PegStabilityModule pegStabilityModule;
  YSS stablecoin;
  ModularToken externalStablecoin;
  address owner;
  uint256 debtCeiling;
  uint8 yssDecimals;
  uint8 externalDecimals;

  function setUp() public {
    owner = msg.sender;
    yssDecimals = 18;
    externalDecimals = 6;
    debtCeiling = 1000000 * (10 ** externalDecimals);
    stablecoin = new YSS();
    externalStablecoin = new ModularToken(0, "ES", "External Stablecoin");
    pegStabilityModule = new PegStabilityModule(
      stablecoin, 
      IERC20(address(externalStablecoin)), 
      debtCeiling, 
      yssDecimals,
      externalDecimals
    );
    stablecoin.setAllowlist(address(pegStabilityModule), true);
    pegStabilityModule.setDebtCeiling(debtCeiling);
  }

  // Test that the setDebtCeiling function works properly
  function testSetDebtCeiling() public {
    uint256 newDebtCeiling = 100000 * (10 ** externalDecimals);
    pegStabilityModule.setDebtCeiling(newDebtCeiling);
    // Check if the debtCeiling is updated
    assertEq(pegStabilityModule.debtCeiling(),
      newDebtCeiling, "Debt ceiling is not properly updated");
  }

  // Test that the deposit function works properly
  function testDeposit() public {
    uint256 extStableAmount = 1000 * (10 ** externalDecimals);
    uint256 yssAmount = 1000 * (10 ** yssDecimals);
    externalStablecoin.mint(address(this), extStableAmount);
    externalStablecoin.approve(address(pegStabilityModule), extStableAmount);
    // Make a deposit
    pegStabilityModule.deposit(extStableAmount);
    // Check if the YSS balance is updated
    assertEq(stablecoin.balanceOf(address(this)),
      yssAmount, "YSS balance is not updated");

    extStableAmount = debtCeiling;
    externalStablecoin.mint(address(this), extStableAmount);
    externalStablecoin.approve(address(pegStabilityModule), extStableAmount);

    vm.expectRevert(bytes("Yama: PSM exceeds debt ceiling"));
    pegStabilityModule.deposit(extStableAmount);
  }

  // Test that the deposit function works properly
  function testWithdraw() public {
    uint256 extStableAmount = 1000 * (10 ** externalDecimals);
    uint256 yssAmount = 1000 * (10 ** yssDecimals);
    externalStablecoin.mint(address(this), extStableAmount);
    externalStablecoin.approve(address(pegStabilityModule), extStableAmount);
    // Make a deposit
    pegStabilityModule.deposit(extStableAmount);
    pegStabilityModule.withdraw(yssAmount);
    // Check if the YSS balance is updated
    assertEq(externalStablecoin.balanceOf(address(this)),
      extStableAmount, "Withdrawal fails");
  }

  function testInsufficientPSMBalance() public {
    uint256 yssAmount = 1000 * (10 ** yssDecimals);
    stablecoin.mint(address(this), yssAmount);
    // Make a withdrawal
    vm.expectRevert(bytes("Yama: PSM reserves insufficient"));
    pegStabilityModule.withdraw(yssAmount);
  }
  
  function testTransfer() public {
    uint256 extStableAmount = 1000 * (10 ** externalDecimals);
    externalStablecoin.mint(address(this), extStableAmount);
    externalStablecoin.approve(address(pegStabilityModule), extStableAmount);
    // Make a deposit
    pegStabilityModule.deposit(extStableAmount);
    pegStabilityModule.transfer(
      externalStablecoin,
      address(this),
      extStableAmount
    );
    // Check if the YSS balance is updated
    assertEq(externalStablecoin.balanceOf(address(this)),
      extStableAmount, "Transfer fails");
  }
}