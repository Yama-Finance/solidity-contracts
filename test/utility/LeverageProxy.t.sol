// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.18;

import "forge-std/Test.sol";
import "src/utility/LeverageProxy.sol";
import "src/periphery/EmptyCollateralManager.sol";
import "src/periphery/PSMPriceSource.sol";
import "../test-contracts/TestSwapper.sol";

contract LeverageProxyTest is Test {
    YSS stablecoin;
    ModularToken collateral;
    CDPModule cdpModule;
    PSMPriceSource psmPriceSource;
    FlashMintModule flashMintModule;
    LeverageProxy proxy;
    TestSwapper swapper;


    function setUp() public {
        stablecoin = new YSS();
        collateral = new ModularToken(0, "Collateral Token", "CT");
        cdpModule = new CDPModule(
            stablecoin,
            new BalanceSheetModule(stablecoin),
            ICollateralManager(address(new EmptyCollateralManager()))
        );
        psmPriceSource = new PSMPriceSource();
        flashMintModule = new FlashMintModule(stablecoin, 1_000_000_000 * PRBMathUD60x18.SCALE);
        stablecoin.setAllowlist(address(cdpModule), true);
        stablecoin.setAllowlist(address(flashMintModule), true);
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
        swapper = new TestSwapper(stablecoin, collateral);
        stablecoin.setAllowlist(address(swapper), true);
        collateral.setAllowlist(address(swapper), true);
        proxy = new LeverageProxy(
            stablecoin,
            flashMintModule,
            cdpModule
        );
        proxy.setCollateralTypeConfig(
            0,
            IERC20(address(collateral)),
            ISwapper(address(swapper))
        );

    }

    function mintAndBorrow(
        uint256 collateralAmount,
        uint256 initialDebt
    ) public returns (uint256 vaultId) {
        collateral.mint(address(this), collateralAmount);
        collateral.approve(address(proxy), collateralAmount);
        vaultId = proxy.createVault(
            0,
            collateralAmount
        );
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

  function testLeverage() public {
    uint256 collateralAmount = 1000 * PRBMathUD60x18.SCALE;
    uint256 initialDebt = 0;
    uint256 vaultId = mintAndBorrow(collateralAmount, initialDebt);
    assertEq(cdpModule.getDebt(vaultId), initialDebt);
    uint256 leverageAmount = 2000 * PRBMathUD60x18.SCALE;
    proxy.leverageUp(vaultId, leverageAmount, leverageAmount);
    assertEq(cdpModule.getDebt(vaultId), leverageAmount);
    assertEq(cdpModule.getCollateralAmount(vaultId), collateralAmount + leverageAmount);

    proxy.leverageDown(vaultId, leverageAmount, leverageAmount);

    assertEq(cdpModule.getDebt(vaultId), 0);
    assertEq(cdpModule.getCollateralAmount(vaultId), collateralAmount);
  }

  function testLeverageDownCompletely() public {
    uint256 collateralAmount = 9000 * PRBMathUD60x18.SCALE;
    uint256 initialDebt = 0;
    uint256 vaultId = mintAndBorrow(collateralAmount, initialDebt);
    assertEq(cdpModule.getDebt(vaultId), initialDebt);
    uint256 leverageAmount = 2000 * PRBMathUD60x18.SCALE;
    proxy.leverageUp(vaultId, leverageAmount, leverageAmount);
    
    vm.warp(block.timestamp + 2);

    proxy.leverageDownAll(vaultId, collateralAmount);

    assertEq(cdpModule.getDebt(vaultId), 0);
  }

  function testSetCollateralTypeConfig() public {
    uint256 collateralAmount = 1000 * PRBMathUD60x18.SCALE;
    uint256 initialDebt = 0;
    uint256 vaultId = mintAndBorrow(collateralAmount, initialDebt);
    assertEq(cdpModule.getDebt(vaultId), initialDebt);
    uint256 leverageAmount = 2000 * PRBMathUD60x18.SCALE;
    proxy.leverageUp(vaultId, leverageAmount, leverageAmount);
    assertEq(cdpModule.getDebt(vaultId), leverageAmount);
    assertEq(cdpModule.getCollateralAmount(vaultId), collateralAmount + leverageAmount);

    proxy.setCollateralTypeConfig(
      0,
      IERC20(address(collateral)),
      ISwapper(address(swapper))
    );

    proxy.leverageDown(vaultId, leverageAmount, leverageAmount);

    assertEq(cdpModule.getDebt(vaultId), 0);
    assertEq(cdpModule.getCollateralAmount(vaultId), collateralAmount);
  }

    function testInvalidFlashLoan() public {
        vm.expectRevert(bytes("SimpleLeverage: Not flashMintModule"));
        proxy.onFlashLoan(address(0), address(0), 0, 0, abi.encodeWithSelector(0));
        vm.expectRevert(bytes("SimpleLeverage: Initiator not this"));
        flashMintModule.flashLoan(proxy, address(stablecoin), 0, abi.encodeWithSelector(0));
    }
}

