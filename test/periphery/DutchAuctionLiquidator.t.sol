// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.18;

import "forge-std/Test.sol";
import "src/modules/CDPModule.sol";
import "src/periphery/EmptyCollateralManager.sol";
import "src/periphery/DutchAuctionLiquidator.sol";
import "src/periphery/PSMPriceSource.sol";

contract DutchAuctionLiquidatorTest is Test {
  using PRBMathUD60x18 for uint256;

  YSS stablecoin;
  BalanceSheetModule balanceSheet;
  CDPModule cdpModule;
  ModularToken collateral;
  DutchAuctionLiquidator liquidator;
  PSMPriceSource psmPriceSource;

  function setUp() public {
    stablecoin = new YSS();
    balanceSheet = new BalanceSheetModule(stablecoin);

    EmptyCollateralManager emptyCollateralManager =
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

  /// @dev This is a utility function, not a test.
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

  function testGetPrice() public {
    uint256 collateralAmount = 1500 * PRBMathUD60x18.SCALE;
    uint256 initialDebt = 1000 * PRBMathUD60x18.SCALE;
    uint256 vaultId = mintAndBorrow(collateralAmount, initialDebt);
    vm.warp(block.timestamp + 5);
    cdpModule.liquidate(vaultId);
    uint256 expectedAuctionPrice = collateralAmount.mul(
      3 * PRBMathUD60x18.HALF_SCALE);
    assertEq(
      liquidator.getPrice(0),
      expectedAuctionPrice,
      "initialPriceRatio"
    );
    vm.warp(block.timestamp + 2);
    expectedAuctionPrice = expectedAuctionPrice.mul(PRBMathUD60x18.HALF_SCALE);
    assertEq(
      liquidator.getPrice(0),
      expectedAuctionPrice,
      "changeRate"
    );
    assertTrue(!liquidator.isExpired(0), "Auction expires prematurely");
  }

  function testResetAuction() public {
    uint256 collateralAmount = 1500 * PRBMathUD60x18.SCALE;
    uint256 initialDebt = 1000 * PRBMathUD60x18.SCALE;
    uint256 vaultId = mintAndBorrow(collateralAmount, initialDebt);
    vm.warp(block.timestamp + 5);
    cdpModule.liquidate(vaultId);
    vm.expectRevert(bytes("Yama: Auction not expired"));
    liquidator.resetAuction(0);  // Unsuccessful reset
    vm.warp(block.timestamp + 10);
    assertTrue(liquidator.isExpired(0), "Auction expiration");
    liquidator.resetAuction(0);  // Successful reset
    vm.expectRevert(bytes("Yama: Auction done"));
    liquidator.claim(0, 0);
  }

  function testClaim() public {
    uint256 collateralAmount = 1500 * PRBMathUD60x18.SCALE;
    uint256 initialDebt = 1000 * PRBMathUD60x18.SCALE;
    uint256 vaultId = mintAndBorrow(collateralAmount, initialDebt);
    vm.warp(block.timestamp + 5);
    cdpModule.liquidate(vaultId);
    uint256 claimAmount = liquidator.getPrice(0);
    stablecoin.mint(address(this), claimAmount);
    vm.expectRevert(bytes("Yama: price > maxPrice"));
    liquidator.claim(0, claimAmount - 1);  // Unsuccessful claim
    liquidator.claim(0, claimAmount);  // Successful claim
    assertEq(collateral.balanceOf(address(this)), collateralAmount);
    assertEq(stablecoin.balanceOf(address(this)), initialDebt);
    vm.expectRevert(bytes("Yama: Auction done"));
    liquidator.resetAuction(0);
  }

  function testSurplusAmount() public {
    uint256 collateralAmount = 1500 * PRBMathUD60x18.SCALE;
    uint256 initialDebt = 1000 * PRBMathUD60x18.SCALE;
    uint256 vaultId = mintAndBorrow(collateralAmount, initialDebt);
    cdpModule.setCollateralType(
      0,
      IPriceSource(address(psmPriceSource)),
      100 * PRBMathUD60x18.SCALE,
      10000 * PRBMathUD60x18.SCALE,
      2 * PRBMathUD60x18.SCALE,
      2 * PRBMathUD60x18.SCALE,
      true,
      false
    );
    uint256 debt = cdpModule.getDebt(vaultId);
    balanceSheet.addDeficit(int256(debt - initialDebt));
    cdpModule.liquidate(vaultId);
    uint256 claimAmount = liquidator.getPrice(0);
    stablecoin.mint(address(this), claimAmount);
    liquidator.claim(0, claimAmount);
    int256 profit = int256(claimAmount) - int256(debt);
    assertTrue(profit > 0);
    assertEq(stablecoin.balanceOf(address(this)), initialDebt);
    assertEq(
      balanceSheet.totalSurplus(),
      int256(profit)
    );
  }

  function testDeficitAmount() public {
    uint256 collateralAmount = 1500 * PRBMathUD60x18.SCALE;
    uint256 initialDebt = 1000 * PRBMathUD60x18.SCALE;
    uint256 vaultId = mintAndBorrow(collateralAmount, initialDebt);
    vm.warp(block.timestamp + 5);
    cdpModule.updateInterest(0);
    uint256 debt = cdpModule.getDebt(vaultId);
    balanceSheet.addDeficit(int256(debt - initialDebt));
    cdpModule.liquidate(vaultId);
    uint256 claimAmount = liquidator.getPrice(0);
    stablecoin.mint(address(this), claimAmount);
    liquidator.claim(0, claimAmount);
    int256 profit = int256(claimAmount) - int256(debt);
    assertTrue(profit < 0);
    assertEq(stablecoin.balanceOf(address(this)), initialDebt);
    assertEq(
      balanceSheet.totalSurplus(),
      int256(profit)
    );
  }

  function testSetCTypeParams() public {
    uint256 collateralAmount = 1500 * PRBMathUD60x18.SCALE;
    uint256 initialDebt = 1000 * PRBMathUD60x18.SCALE;
    uint256 vaultId = mintAndBorrow(collateralAmount, initialDebt);
    vm.warp(block.timestamp + 5);
    liquidator.setCTypeParams(
      0,
      3 * PRBMathUD60x18.HALF_SCALE,
      2,
      PRBMathUD60x18.HALF_SCALE,
      5,
      true
    );
    cdpModule.liquidate(vaultId);
    uint256 claimAmount = liquidator.getPrice(0);
    stablecoin.mint(address(this), claimAmount);
    liquidator.claim(0, claimAmount);
  }

  function testSetDefaultCTypeParams() public {
    uint256 collateralAmount = 1500 * PRBMathUD60x18.SCALE;
    uint256 initialDebt = 1000 * PRBMathUD60x18.SCALE;
    uint256 vaultId = mintAndBorrow(collateralAmount, initialDebt);
    vm.warp(block.timestamp + 5);
    liquidator.setDefaultCTypeParams(
      3 * PRBMathUD60x18.HALF_SCALE,
      2,
      PRBMathUD60x18.HALF_SCALE,
      5
    );
    cdpModule.liquidate(vaultId);
    uint256 claimAmount = liquidator.getPrice(0);
    stablecoin.mint(address(this), claimAmount);

    liquidator.claim(0, claimAmount);
  }

  // Claim expired auction
  function testClaimExpired() public {
    uint256 collateralAmount = 1500 * PRBMathUD60x18.SCALE;
    uint256 initialDebt = 1000 * PRBMathUD60x18.SCALE;
    uint256 vaultId = mintAndBorrow(collateralAmount, initialDebt);
    vm.warp(block.timestamp + 5);
    cdpModule.liquidate(vaultId);
    vm.expectRevert(bytes("Yama: Vault already liquidated"));
    cdpModule.liquidate(vaultId);
    uint256 claimAmount = liquidator.getPrice(0);
    stablecoin.mint(address(this), claimAmount);
    vm.warp(block.timestamp + 10);
    vm.expectRevert(bytes("Yama: Auction expired"));
    liquidator.claim(0, claimAmount);

    assertEq(liquidator.getPrice(0), 0);
    assertEq(liquidator.getCollateralAmount(0), collateralAmount);
    assertEq(liquidator.getLastAuctionId(), 0);
  }


}