// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.18;

import "forge-std/Test.sol";
import "src/modules/CDPModule.sol";
import "src/periphery/EmptyCollateralManager.sol";
import "src/periphery/DutchAuctionLiquidator.sol";
import "src/periphery/PSMPriceSource.sol";
import "test/test-contracts/TestLiquidator.sol";

contract CDPTest is Test {
  using PRBMathUD60x18 for uint256;
  YSS stablecoin;
  BalanceSheetModule balanceSheet;
  CDPModule cdpModule;
  ModularToken collateral;
  PSMPriceSource psmPriceSource;
  DutchAuctionLiquidator liquidator;
  EmptyCollateralManager emptyCollateralManager;

  function setUp() public {
    stablecoin = new YSS();
    balanceSheet = new BalanceSheetModule(stablecoin);

    emptyCollateralManager =
      new EmptyCollateralManager();
    psmPriceSource = new PSMPriceSource();

    cdpModule = new CDPModule(
      stablecoin,
      balanceSheet,
      ICollateralManager(address(emptyCollateralManager))
    );

    liquidator = new DutchAuctionLiquidator(
      stablecoin,
      balanceSheet,
      cdpModule,
      3 * PRBMathUD60x18.HALF_SCALE,
      2,
      PRBMathUD60x18.HALF_SCALE,
      5
    );

    ILiquidator[] memory liquidators = new ILiquidator[](1);
    liquidators[0] = ILiquidator(address(liquidator));
    cdpModule.setLiquidators(liquidators);
    stablecoin.setAllowlist(address(cdpModule), true);
    stablecoin.setAllowlist(address(liquidator), true);

    collateral = new ModularToken(0, "Collateral Token", "CT");

    cdpModule.addCollateralType(
      IERC20(collateral),
      IPriceSource(address(psmPriceSource)),
      100 * PRBMathUD60x18.SCALE,
      10000 * PRBMathUD60x18.SCALE,
      PRBMathUD60x18.SCALE + PRBMathUD60x18.HALF_SCALE,
      2 * PRBMathUD60x18.SCALE,
      true,
      false
    );
  }

  function mintAndBorrow(
    uint256 collateralAmount,
    uint256 initialDebt
  ) public returns (uint256 vaultId) {
    collateral.mint(address(this), collateralAmount);
    collateral.approve(address(cdpModule), collateralAmount);
    vaultId = cdpModule.createVault(
      0,
      collateralAmount,
      address(0)
    );
    cdpModule.borrow(vaultId, initialDebt);
  }

  function mintAndBorrowRevert(
    uint256 collateralAmount,
    uint256 initialDebt,
    bytes memory revertMsg
  ) public returns (uint256 vaultId) {
    collateral.mint(address(this), collateralAmount);
    collateral.approve(address(cdpModule), collateralAmount);
    vaultId = cdpModule.createVault(
      0,
      collateralAmount,
      address(0)
    );
    vm.expectRevert(revertMsg);
    cdpModule.borrow(vaultId, initialDebt);
  }

  function testRemoveCollateral() public {
    uint256 collateralAmount = 1000 * PRBMathUD60x18.SCALE;
    uint256 initialDebt = 100 * PRBMathUD60x18.SCALE;
    uint256 vaultId = mintAndBorrow(collateralAmount, initialDebt);
    assertEq(cdpModule.getCollateralAmount(vaultId), collateralAmount);
    uint256 collateralAmount2 = 1000 * PRBMathUD60x18.SCALE;
    collateral.mint(address(this), collateralAmount2);
    collateral.approve(address(cdpModule), collateralAmount2);
    cdpModule.addCollateral(vaultId, collateralAmount2);
    assertEq(cdpModule.getCollateralAmount(vaultId), collateralAmount + collateralAmount2);
    cdpModule.removeCollateral(vaultId, collateralAmount2);
    assertEq(cdpModule.getCollateralAmount(vaultId), collateralAmount);
  }

  function testRepay() public {
    uint256 collateralAmount = 1000 * PRBMathUD60x18.SCALE;
    uint256 initialDebt = 200 * PRBMathUD60x18.SCALE;
    uint256 vaultId = mintAndBorrow(collateralAmount, initialDebt);
    assertEq(cdpModule.getDebt(vaultId), initialDebt);
    uint256 repayAmount = 50 * PRBMathUD60x18.SCALE;
    stablecoin.mint(address(this), repayAmount);
    stablecoin.approve(address(cdpModule), repayAmount);
    cdpModule.repay(vaultId, repayAmount);

    assertEq(cdpModule.getDebt(vaultId), initialDebt - repayAmount);

    repayAmount = 100 * PRBMathUD60x18.SCALE;
    stablecoin.mint(address(this), repayAmount);
    stablecoin.approve(address(cdpModule), repayAmount);
    vm.expectRevert(bytes("Yama: Invalid debt amount"));
    cdpModule.repay(vaultId, repayAmount);
  }

  function testBadLiquidation() public {
    uint256 collateralAmount = 1500 * PRBMathUD60x18.SCALE;
    uint256 initialDebt = 1000 * PRBMathUD60x18.SCALE;
    uint256 vaultId = mintAndBorrow(collateralAmount, initialDebt);
    vm.expectRevert(bytes("Yama: Vault not undercollateralized"));
    cdpModule.liquidate(vaultId);
  }

  function testUndercollateralized() public {
    uint256 collateralAmount = 1500 * PRBMathUD60x18.SCALE;
    uint256 initialDebt = 1000 * PRBMathUD60x18.SCALE;
    uint256 vaultId = mintAndBorrow(collateralAmount, initialDebt);
    assertTrue(!cdpModule.underCollateralized(vaultId));
    vm.warp(block.timestamp + 1);
    cdpModule.updateInterest(0);
    assertTrue(cdpModule.underCollateralized(vaultId));
  }

  // Test interest accrual
  function testInterestAccrual() public {
    uint256 initialDebt = 100 * PRBMathUD60x18.SCALE;
    uint256 collateralAmount = initialDebt * 10;
    uint256 vaultId = mintAndBorrow(collateralAmount, initialDebt);

    assertEq(cdpModule.getDebt(vaultId), initialDebt);
    cdpModule.updateInterest(0);
    assertEq(cdpModule.getDebt(vaultId), initialDebt);
    vm.warp(block.timestamp + 1);
    cdpModule.updateInterest(0);
    assertEq(cdpModule.getDebt(vaultId), initialDebt * 2);
    assertEq(balanceSheet.totalSurplus(), int256(initialDebt));
    stablecoin.mint(address(this), initialDebt);
    stablecoin.approve(address(cdpModule), initialDebt * 2);
    cdpModule.repay(vaultId, initialDebt * 2);
    assertEq(cdpModule.getDebt(vaultId), 0);
    cdpModule.removeCollateral(vaultId, collateralAmount);
    assertEq(collateral.balanceOf(address(this)), collateralAmount);
  }

  // Test interest accrual with multiple vaults
  function testInterestAccrualMultipleVaults() public {
    uint256 initialDebt = 100 * PRBMathUD60x18.SCALE;
    uint256 collateralAmount = initialDebt * 10;
    uint256 vaultId = mintAndBorrow(collateralAmount, initialDebt);
    uint256 vaultId2 = mintAndBorrow(collateralAmount, initialDebt * 2);

    assertEq(cdpModule.getDebt(vaultId), initialDebt);
    assertEq(cdpModule.getDebt(vaultId2), initialDebt * 2);
    cdpModule.updateInterest(0);
    assertEq(cdpModule.getDebt(vaultId), initialDebt);
    assertEq(cdpModule.getDebt(vaultId2), initialDebt * 2);
    vm.warp(block.timestamp + 1);
    cdpModule.updateInterest(0);
    assertEq(cdpModule.getDebt(vaultId), initialDebt * 2);
    assertEq(cdpModule.getDebt(vaultId2), initialDebt * 4);
    assertEq(balanceSheet.totalSurplus(), int256(initialDebt * 3));
    stablecoin.mint(address(this), initialDebt * 4);
    stablecoin.approve(address(cdpModule), initialDebt * 6);
    cdpModule.repay(vaultId, initialDebt * 2);
    cdpModule.repay(vaultId2, initialDebt * 4);
    assertEq(cdpModule.getDebt(vaultId), 0);
    assertEq(cdpModule.getDebt(vaultId2), 0);
    cdpModule.removeCollateral(vaultId, collateralAmount);
    cdpModule.removeCollateral(vaultId2, collateralAmount);
    assertEq(collateral.balanceOf(address(this)), collateralAmount * 2);
  }

  // Test borrowing disabled
  function testBorrowingDisabled() public {
    uint256 loanAmount = 1000 * PRBMathUD60x18.SCALE;
    cdpModule.setBorrowingDisabled(true);
    uint256 collateralAmount = loanAmount * 2;
    mintAndBorrowRevert(collateralAmount, loanAmount,
      bytes("Yama: Borrowing disabled"));
    cdpModule.setBorrowingDisabled(false);
    uint256 vaultId = mintAndBorrow(collateralAmount, loanAmount);
    assertEq(cdpModule.getDebt(vaultId), loanAmount);

    cdpModule.setCollateralType(
      0,
      IPriceSource(address(psmPriceSource)),
      100 * PRBMathUD60x18.SCALE,
      10000 * PRBMathUD60x18.SCALE,
      PRBMathUD60x18.SCALE + PRBMathUD60x18.HALF_SCALE,
      2 * PRBMathUD60x18.SCALE,
      false,
      false
    );
    mintAndBorrowRevert(collateralAmount, loanAmount, "Yama: Collateral type disabled");
  }

  function testRemoveCollateralUndercollateralized() public {
    uint256 loanAmount = 1000 * PRBMathUD60x18.SCALE;
    uint256 collateralAmount = loanAmount * 2;
    uint256 vaultId = mintAndBorrow(collateralAmount, loanAmount);
    vm.expectRevert(bytes("Yama: Vault undercollateralized"));
    cdpModule.removeCollateral(vaultId, collateralAmount);
  }

  // Test allowlist
  function testAllowlist() public {
    uint256 loanAmount = 1000 * PRBMathUD60x18.SCALE;
    cdpModule.setCollateralType(
      0,
      IPriceSource(address(psmPriceSource)),
      100 * PRBMathUD60x18.SCALE,
      10000 * PRBMathUD60x18.SCALE,
      PRBMathUD60x18.SCALE + PRBMathUD60x18.HALF_SCALE,
      2 * PRBMathUD60x18.SCALE,
      true,
      true
    );
    uint256 collateralAmount = loanAmount * 2;
    mintAndBorrowRevert(collateralAmount, loanAmount,
      bytes("Yama: Not allowed borrower"));
    cdpModule.setAllowedBorrower(0, address(this), true);
    uint256 vaultId = mintAndBorrow(collateralAmount, loanAmount);
    assertEq(cdpModule.getDebt(vaultId), loanAmount);
  }

  // Test debt ceiling
  function testDebtCeiling() public {
    uint256 loanAmount = 10001 * PRBMathUD60x18.SCALE;
    uint256 collateralAmount = loanAmount * 2;
    mintAndBorrowRevert(collateralAmount, loanAmount,
      bytes("Yama: Debt ceiling exceeded"));
  }

  // Test creating an undercollateralized vault
  function testUndercollateralizedVaultCreation() public {
    uint256 loanAmount = 1000 * PRBMathUD60x18.SCALE;
    uint256 collateralAmount = loanAmount;
    mintAndBorrowRevert(collateralAmount, loanAmount,
      bytes("Yama: Invalid debt amount"));
  }

  // Test debt floor
  function testDebtFloor() public {
    uint256 loanAmount = 99 * PRBMathUD60x18.SCALE;
    uint256 collateralAmount = loanAmount * 2;
    mintAndBorrowRevert(collateralAmount, loanAmount,
      bytes("Yama: Invalid debt amount"));
  }

  function testNoLiquidators() public {
    uint256 loanAmount = 1000 * PRBMathUD60x18.SCALE;
    uint256 collateralAmount = loanAmount * 2;
    uint256 vaultId = mintAndBorrow(collateralAmount, loanAmount);
    ILiquidator[] memory liquidators = new ILiquidator[](0);
    cdpModule.setLiquidators(liquidators);
    vm.warp(block.timestamp + 2);
    vm.expectRevert(bytes("Yama: No liquidator accepted the liquidation"));
    cdpModule.liquidate(vaultId);
  }

  function testSetCollateralManager() public {
    cdpModule.setCollateralManager(emptyCollateralManager);
  }

  function testAddCollateralType() public {
    cdpModule.addCollateralType(
      IERC20(collateral),
      IPriceSource(address(psmPriceSource)),
      100 * PRBMathUD60x18.SCALE,
      10000 * PRBMathUD60x18.SCALE,
      PRBMathUD60x18.SCALE + PRBMathUD60x18.HALF_SCALE,
      2 * PRBMathUD60x18.SCALE,
      false,
      false
    );
  }

  function testReadInfo() public {
    uint256 loanAmount = 1000 * PRBMathUD60x18.SCALE;
    uint256 collateralAmount = loanAmount * 2;
    uint256 vaultId = mintAndBorrow(collateralAmount, loanAmount);
    assertEq(cdpModule.isLiquidated(vaultId), false);
    assertEq(cdpModule.getCollateralAmount(vaultId), collateralAmount);
    assertEq(cdpModule.getOwnedVaults(address(this)).length, 1);
    assertEq(cdpModule.getOwner(vaultId), address(this));
    assertEq(cdpModule.getAltOwner(vaultId), address(0));


    uint256 collateralTypeId = cdpModule.addCollateralType(
      IERC20(collateral),
      IPriceSource(address(psmPriceSource)),
      100 * PRBMathUD60x18.SCALE,
      10000 * PRBMathUD60x18.SCALE,
      PRBMathUD60x18.SCALE + PRBMathUD60x18.HALF_SCALE,
      1000000001000000000,
      false,
      false
    );

    assertEq(cdpModule.getAnnualInterest(collateralTypeId), 1032038528297637478);
    assertEq(cdpModule.getPsInterest(collateralTypeId), 1000000001000000000);
    assertEq(cdpModule.getCollateralRatio(collateralTypeId), PRBMathUD60x18.SCALE + PRBMathUD60x18.HALF_SCALE);
    assertEq(cdpModule.getDebtFloor(collateralTypeId), 100 * PRBMathUD60x18.SCALE);
    assertEq(cdpModule.getDebtCeiling(collateralTypeId), 10000 * PRBMathUD60x18.SCALE);

  }

  function testLiquidatorReturnsFalse() public {
    uint256 loanAmount = 1000 * PRBMathUD60x18.SCALE;
    uint256 collateralAmount = loanAmount * 2;
    uint256 vaultId = mintAndBorrow(collateralAmount, loanAmount);
    ILiquidator[] memory liquidators = new ILiquidator[](1);
    liquidators[0] = ILiquidator(address(new TestLiquidator()));
    cdpModule.setLiquidators(liquidators);
    vm.warp(block.timestamp + 2);
    vm.expectRevert(bytes("Yama: No liquidator accepted the liquidation"));
    cdpModule.liquidate(vaultId);
  }

  function testAccessVaultNotOwner() public {
    uint256 loanAmount = 1000 * PRBMathUD60x18.SCALE;
    uint256 collateralAmount = loanAmount * 2;
    uint256 vaultId = mintAndBorrow(collateralAmount, loanAmount);
    vm.prank(address(1));
    vm.expectRevert(bytes("Yama: Must be vault owner"));
    cdpModule.borrow(vaultId, 1 * PRBMathUD60x18.SCALE);
  }

  function testNegativeInterest() public {
    cdpModule.setCollateralType(
      0,
      IPriceSource(address(psmPriceSource)),
      100 * PRBMathUD60x18.SCALE,
      10000 * PRBMathUD60x18.SCALE,
      PRBMathUD60x18.SCALE + PRBMathUD60x18.HALF_SCALE,
      PRBMathUD60x18.HALF_SCALE,
      true,
      false
    );
    uint256 loanAmount = 1000 * PRBMathUD60x18.SCALE;
    uint256 collateralAmount = loanAmount * 2;
    uint256 vaultId = mintAndBorrow(collateralAmount, loanAmount);
    vm.warp(block.timestamp + 1);
    cdpModule.updateInterest(vaultId);
    assertEq(cdpModule.getDebt(vaultId), 500 * PRBMathUD60x18.SCALE);
    assertEq(balanceSheet.totalSurplus(), -int256(500 * PRBMathUD60x18.SCALE));
  }
}
