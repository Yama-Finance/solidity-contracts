// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.18;

import "forge-std/Test.sol";
import "src/gov/InterestController.sol";
import "src/periphery/EmptyCollateralManager.sol";
import "src/periphery/PSMPriceSource.sol";

contract InterestControllerTest is Test {
  YSS stablecoin;
  BalanceSheetModule balanceSheet;
  CDPModule cdpModule;
  ModularToken collateral;
  PSMPriceSource psmPriceSource;
  InterestController interestController;
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

    stablecoin.setAllowlist(address(cdpModule), true);

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

    interestController = new InterestController(
      stablecoin,
      cdpModule,
      address(this),
      10 ** 18,
      1000000021979553151 // 150% interest
    );

    stablecoin.setAllowlist(address(interestController), true);
  }
  
  function testSetInterestRate() public {
    interestController.setInterestRate(0, 1000000021979553151);
  }

  function testFailSetInterestRateHigh() public {
    interestController.setInterestRate(0, 1000000021979553151 + 1);
  }

  function testFailSetInterestRateLow() public {
    interestController.setInterestRate(0, 10 ** 18 - 1);
  }

  function testSetMaintainer() public {
    interestController.setMaintainer(address(this));
  }

  function testFailNotMaintainer() public {
    interestController.setMaintainer(address(0));
    interestController.setInterestRate(0, 10 ** 18);
  }
}