// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.18;

import "forge-std/Test.sol";
import "src/periphery/PSMLockup.sol";
import "src/periphery/SimpleBSH.sol";

contract PSMLockupTest is Test {
  BalanceSheetModule balanceSheet;
  YSS stablecoin;
  PegStabilityModule psm;
  PSMLockup lockup;
  ModularToken token;
  SimpleBSH bsh;

  uint256 amountMint;

  function setUp() public {
    stablecoin = new YSS();
    balanceSheet = new BalanceSheetModule(stablecoin);
    token = new ModularToken(1_000_000 * 10 ** 18, "Test USDC", "TUSDC");
    psm = new PegStabilityModule(
      stablecoin,
      token,
      1_000_000 * 10 ** 18,
      18,
      18
    );
    lockup = new PSMLockup(
      stablecoin,
      psm,
      token,
      "PSM Lockup",
      "PSML"
    );
    bsh = new SimpleBSH(
      stablecoin,
      balanceSheet,
      5000,
      address(lockup)
    );
    lockup.setBSH(bsh);
    balanceSheet.setHandler(IBalanceSheetHandler(address(bsh)));
    stablecoin.setAllowlist(address(psm), true);
    stablecoin.setAllowlist(address(bsh), true);
  }

  function testLockup() public {
    amountMint = token.balanceOf(address(this));
    token.approve(address(lockup), amountMint);
    assertEq(lockup.value(), 10 ** 18);
    lockup.lockup(amountMint);
    assertEq(stablecoin.balanceOf(address(this)), 0);
    assertEq(token.balanceOf(address(this)), 0);
    assertEq(lockup.balanceOf(address(this)), amountMint);
    assertEq(lockup.value(), 10 ** 18);
    lockup.withdraw(amountMint);
    assertEq(stablecoin.balanceOf(address(this)), amountMint);
    assertEq(token.balanceOf(address(this)), 0);
    assertEq(lockup.balanceOf(address(this)), 0);
  }

  function testLockupWithProfit() public {
    amountMint = token.balanceOf(address(this));
    token.approve(address(lockup), amountMint);
    lockup.lockup(amountMint);
    assertEq(stablecoin.balanceOf(address(this)), 0);
    assertEq(token.balanceOf(address(this)), 0);
    assertEq(lockup.balanceOf(address(this)), amountMint);
    balanceSheet.addSurplus(int256(amountMint));
    vm.roll(block.number + 1);
    bsh.processPendingShareAmount();
    assertEq(stablecoin.balanceOf(address(lockup)), amountMint + (amountMint / 2));
    assertEq(lockup.value(), 10 ** 18 + (10 ** 18 / 2));
    lockup.withdraw(amountMint);
    assertEq(stablecoin.balanceOf(address(this)), amountMint + (amountMint / 2));
    assertEq(lockup.value(), 10 ** 18);
    assertEq(token.balanceOf(address(this)), 0);
    assertEq(lockup.balanceOf(address(this)), 0);
  }
}